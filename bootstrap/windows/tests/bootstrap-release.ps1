[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-BootstrapReleaseTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Bootstrap Release test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $RepositoryRoot 'data'
}
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')

$TestRoot = Join-Path $RepositoryRoot (
    "data\_test\bootstrap-release-$([Guid]::NewGuid().ToString('N'))"
)
try {
    $SharedContext = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Contracts = @(Get-SwawHarnessWindowsProductContracts `
        -WindowsRoot $WindowsRoot `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $SharedContext `
        -Contract $PlatformContract
    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -InstallRoot $InstallRoot
    if ($null -eq $Toolchain) {
        throw 'Bootstrap Release test requires the Contract toolchain.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain

    $CoreCandidatePath = & (Join-Path $WindowsRoot 'core\build.ps1') `
        -DataRoot $TestRoot `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryCandidatePath = & (Join-Path $WindowsRoot 'entry\build.ps1') `
        -DataRoot $TestRoot `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryManagerCandidatePath = & (
        Join-Path $WindowsRoot 'entry.manager\build.ps1'
    ) `
        -DataRoot $TestRoot `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1

    $Arguments = @{
        DataRoot = $TestRoot
        CoreCandidatePath = [string]$CoreCandidatePath
        EntryCandidatePath = [string]$EntryCandidatePath
        EntryManagerCandidatePath = [string]$EntryManagerCandidatePath
    }
    $First = Publish-SwawHarnessWindowsProducts @Arguments
    $FirstCreated = (Get-Item -LiteralPath $First.Root).CreationTimeUtc
    $Second = Publish-SwawHarnessWindowsProducts @Arguments
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $TestRoot
    $Selected = Read-SwawHarnessSelectedRelease `
        -ReleasesRoot $Context.BootstrapReleaseRoot `
        -Contracts $Contracts

    $ReleaseDirectories = @(
        Get-ChildItem -LiteralPath $Context.BootstrapReleaseRoot `
            -Directory -Force
    )
    $ExpectedNames = @($Contracts | ForEach-Object { $_.ProductBinary })
    $ActualNames = @($Selected.Artifacts | ForEach-Object { $_.Name })
    Assert-BootstrapReleaseTest `
        -Condition (
            [string]$First.ReleaseId -ceq [string]$Second.ReleaseId -and
            [string]$Selected.ReleaseId -ceq [string]$First.ReleaseId -and
            $ReleaseDirectories.Count -eq 1 -and
            (Get-Item -LiteralPath $Second.Root).CreationTimeUtc -eq
                $FirstCreated -and
            $Selected.Artifacts.Count -eq 3 -and
            [string]::Join('|', $ActualNames) -ceq
                [string]::Join('|', $ExpectedNames)
        ) `
        -Message 'bundle publication is not complete, immutable, and idempotent'
    $Selector = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-BootstrapReleaseTest `
        -Condition ($Selector -ceq [string]$First.ReleaseId) `
        -Message 'the target selector does not select the bundle Release'

    foreach ($Artifact in $Selected.Artifacts) {
        [void](Assert-SwawHarnessNoExternalCrtImports `
            -ArtifactPath $Artifact.Path `
            -LinkerPath $Plan.LinkerPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
    }
    $CoreArtifact = @($Selected.Artifacts | Where-Object {
        $_.Name -ceq 'swaw-harness-helloworld.exe'
    })[0]
    $Output = & $CoreArtifact.Path 'Bootstrap'
    Assert-BootstrapReleaseTest `
        -Condition (
            $LASTEXITCODE -eq 0 -and
            [string]$Output -ceq 'Hello, Bootstrap!'
        ) `
        -Message 'the bundled Core executable did not run correctly'

    $Candidate = Get-Content -Raw -LiteralPath $CoreCandidatePath |
        ConvertFrom-Json
    $Candidate.artifact.length = [long]$Candidate.artifact.length + 1
    [IO.File]::WriteAllText(
        $CoreCandidatePath,
        (($Candidate | ConvertTo-Json -Depth 8) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
    $Rejected = $false
    try {
        [void](Publish-SwawHarnessWindowsProducts @Arguments)
    } catch {
        $Rejected = $true
    }
    Assert-BootstrapReleaseTest `
        -Condition $Rejected `
        -Message 'bundle publication accepted a tampered Candidate'
    $SelectorAfterFailure = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-BootstrapReleaseTest `
        -Condition ($SelectorAfterFailure -ceq [string]$First.ReleaseId) `
        -Message 'failed bundle publication changed the selector'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap bundle Release' -ForegroundColor Green
