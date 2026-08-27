[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ReleaseSafetyTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Release safety test failed: $Message"
    }
}

function New-ReleaseSafetyFixture {
    param(
        [string]$Name,
        [string]$Content,
        [string]$Root,
        [string]$TargetId
    )

    $Path = Join-Path $Root $Name
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    $Item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        Contract = [pscustomobject][ordered]@{
            TargetId = $TargetId
            ProductBinary = $Name
            MaximumBytes = 1MB
        }
        Candidate = [pscustomobject][ordered]@{
            TargetId = $TargetId
            Name = $Name
            ArtifactPath = $Path
            Length = [long]$Item.Length
            Sha256 = Get-SwawHarnessFileSha256 -Path $Path
        }
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\release\publication.ps1')

$TestRoot = Join-Path $RepositoryRoot (
    "data\_test\release-safety-$([Guid]::NewGuid().ToString('N'))"
)
try {
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $TestRoot
    $FixtureRoot = Join-Path $Context.BootstrapWindowsCacheRoot 'fixtures'
    [void][IO.Directory]::CreateDirectory($FixtureRoot)
    $TargetId = 'x86_64-pc-windows-msvc'
    $Fixtures = @(
        New-ReleaseSafetyFixture `
            -Name 'core.exe' -Content 'core-a' `
            -Root $FixtureRoot -TargetId $TargetId
        New-ReleaseSafetyFixture `
            -Name 'entry.exe' -Content 'entry-a' `
            -Root $FixtureRoot -TargetId $TargetId
        New-ReleaseSafetyFixture `
            -Name 'entry-manager.exe' -Content 'manager-a' `
            -Root $FixtureRoot -TargetId $TargetId
    )
    $Contracts = @($Fixtures | ForEach-Object { $_.Contract })
    $Candidates = @($Fixtures | ForEach-Object { $_.Candidate })

    $First = Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates
    $FirstCreated = (Get-Item -LiteralPath $First.Root).CreationTimeUtc
    $Second = Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates
    Assert-ReleaseSafetyTest `
        -Condition (
            $First.ReleaseId -ceq $Second.ReleaseId -and
            (Get-Item -LiteralPath $Second.Root).CreationTimeUtc -eq
                $FirstCreated -and
            $Second.Artifacts.Count -eq 3
        ) `
        -Message 'identical content did not reuse one complete Release'

    $PreviousSelector = [IO.File]::ReadAllText($First.SelectorPath)
    $InvalidCandidates = @($Candidates)
    $InvalidCandidates[2] = [pscustomobject][ordered]@{
        TargetId = $TargetId
        Name = 'entry-manager.exe'
        ArtifactPath = Join-Path $FixtureRoot 'missing.exe'
        Length = 1
        Sha256 = '0' * 64
    }
    $Rejected = $false
    try {
        [void](Publish-SwawHarnessBootstrapRelease `
            -Context $Context `
            -Contracts $Contracts `
            -Candidates $InvalidCandidates)
    } catch {
        $Rejected = $true
    }
    Assert-ReleaseSafetyTest `
        -Condition (
            $Rejected -and
            [IO.File]::ReadAllText($First.SelectorPath) -ceq $PreviousSelector
        ) `
        -Message 'incomplete input changed the selected Release'

    $UnexpectedPath = Join-Path $First.Root 'unexpected.bin'
    [IO.File]::WriteAllText($UnexpectedPath, 'unexpected')
    $Rejected = $false
    try {
        [void](Read-SwawHarnessSelectedRelease `
            -ReleasesRoot $Context.BootstrapReleaseRoot `
            -Contracts $Contracts)
    } catch {
        $Rejected = $true
    }
    Assert-ReleaseSafetyTest `
        -Condition $Rejected `
        -Message 'a Release with unexpected membership was accepted'
    [IO.File]::Delete($UnexpectedPath)

    $CorruptArtifact = @($First.Artifacts | Where-Object {
        $_.Name -ceq 'entry.exe'
    })[0]
    [IO.File]::WriteAllText($CorruptArtifact.Path, 'corrupt')
    $Repaired = Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates
    Assert-ReleaseSafetyTest `
        -Condition (
            $Repaired.ReleaseId -ceq $First.ReleaseId -and
            (Get-SwawHarnessFileSha256 -Path $CorruptArtifact.Path) -ceq
                $Candidates[1].Sha256
        ) `
        -Message 'a corrupt content-addressed Release was not rebuilt'

    [IO.File]::Delete($Repaired.SelectorPath)
    [void][IO.Directory]::CreateDirectory($Repaired.SelectorPath)
    $AfterUnsafeSelector = Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates
    Assert-ReleaseSafetyTest `
        -Condition (
            [IO.File]::Exists($AfterUnsafeSelector.SelectorPath) -and
            -not [IO.Directory]::Exists($AfterUnsafeSelector.SelectorPath) -and
            [IO.File]::ReadAllText($AfterUnsafeSelector.SelectorPath).Trim() -ceq
                $First.ReleaseId
        ) `
        -Message 'an unsafe selector was not replaced with a regular file'

    $InterruptedRoot = Join-Path $Context.BootstrapReleaseRoot (
        '.publish-11111111111111111111111111111111.tmp'
    )
    [void][IO.Directory]::CreateDirectory($InterruptedRoot)
    [IO.File]::WriteAllText((Join-Path $InterruptedRoot 'partial'), 'partial')
    [void](Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates)
    Assert-ReleaseSafetyTest `
        -Condition (-not [IO.Directory]::Exists($InterruptedRoot)) `
        -Message 'interrupted publication work was not cleaned under the lock'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap Release safety' -ForegroundColor Green
