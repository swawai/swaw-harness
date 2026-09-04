[CmdletBinding()]
param([string]$DataRepo = '')

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
        [string]$PlatformTargetId
    )

    $Path = Join-Path $Root $Name
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    $Item = Get-Item -LiteralPath $Path
    return [pscustomobject][ordered]@{
        Contract = [pscustomobject][ordered]@{
            PlatformTargetId = $PlatformTargetId
            ProductBinary = $Name
            MaximumBytes = 1MB
        }
        Candidate = [pscustomobject][ordered]@{
            PlatformTargetId = $PlatformTargetId
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

. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot
    $FixtureRoot = Join-Path $Context.BuildRoot 'fixtures'
    [void][IO.Directory]::CreateDirectory($FixtureRoot)
    $PlatformTargetId = 'x86_64-pc-windows-msvc'
    $Fixtures = @(
        New-ReleaseSafetyFixture `
            -Name 'core.exe' -Content 'core-a' `
            -Root $FixtureRoot -PlatformTargetId $PlatformTargetId
        New-ReleaseSafetyFixture `
            -Name 'user.exe' -Content 'user-a' `
            -Root $FixtureRoot -PlatformTargetId $PlatformTargetId
        New-ReleaseSafetyFixture `
            -Name 'host.exe' -Content 'host-a' `
            -Root $FixtureRoot -PlatformTargetId $PlatformTargetId
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
        PlatformTargetId = $PlatformTargetId
        Name = 'host.exe'
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
        $_.Name -ceq 'user.exe'
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

    $OtherPlatformTargetId = 'aarch64-pc-windows-msvc'
    $InterruptedRoot = Join-Path $Context.BootstrapReleaseRoot (
        ".publish-$PlatformTargetId-11111111111111111111111111111111.tmp"
    )
    $OtherInterruptedRoot = Join-Path $Context.BootstrapReleaseRoot (
        ".publish-$OtherPlatformTargetId-22222222222222222222222222222222.tmp"
    )
    foreach ($Path in @($InterruptedRoot, $OtherInterruptedRoot)) {
        [void][IO.Directory]::CreateDirectory($Path)
        [IO.File]::WriteAllText((Join-Path $Path 'partial'), 'partial')
    }
    [void](Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates)
    Assert-ReleaseSafetyTest `
        -Condition (
            -not [IO.Directory]::Exists($InterruptedRoot) -and
            [IO.Directory]::Exists($OtherInterruptedRoot)
        ) `
        -Message 'publication cleanup crossed a platform target boundary'

    $OtherFixtureRoot = Join-Path $FixtureRoot $OtherPlatformTargetId
    [void][IO.Directory]::CreateDirectory($OtherFixtureRoot)
    $OtherFixtures = @(
        New-ReleaseSafetyFixture `
            -Name 'core.exe' -Content 'core-b' `
            -Root $OtherFixtureRoot `
            -PlatformTargetId $OtherPlatformTargetId
        New-ReleaseSafetyFixture `
            -Name 'user.exe' -Content 'user-b' `
            -Root $OtherFixtureRoot `
            -PlatformTargetId $OtherPlatformTargetId
        New-ReleaseSafetyFixture `
            -Name 'host.exe' -Content 'host-b' `
            -Root $OtherFixtureRoot `
            -PlatformTargetId $OtherPlatformTargetId
    )
    $OtherContracts = @($OtherFixtures | ForEach-Object { $_.Contract })
    $OtherCandidates = @($OtherFixtures | ForEach-Object { $_.Candidate })
    $OtherRelease = Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $OtherContracts `
        -Candidates $OtherCandidates
    Assert-ReleaseSafetyTest `
        -Condition (
            -not [IO.Directory]::Exists($OtherInterruptedRoot) -and
            [IO.File]::ReadAllText($First.SelectorPath).Trim() -ceq
                $First.ReleaseId -and
            [IO.File]::ReadAllText($OtherRelease.SelectorPath).Trim() -ceq
                $OtherRelease.ReleaseId
        ) `
        -Message 'platform-target publication cleanup or selection was not isolated'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap Release safety' -ForegroundColor Green
