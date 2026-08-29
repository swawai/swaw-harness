[CmdletBinding()]
param([string]$DataRepo = '')

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
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $WindowsRoot 'core\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry.manager\candidate-build.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $SharedContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
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

    $Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot
    $CoreCandidateRoot = Invoke-SwawHarnessWindowsCoreCandidateBuild `
        -Context $Context `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryCandidateRoot = Invoke-SwawHarnessWindowsEntryCandidateBuild `
        -Context $Context `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryManagerCandidateRoots = @(
        Invoke-SwawHarnessWindowsEntryManagerCandidateBuild `
        -Context $Context `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    $CandidateRoots = @(
        [string]$CoreCandidateRoot,
        [string]$EntryCandidateRoot,
        [string]$EntryManagerCandidateRoots[0],
        [string]$EntryManagerCandidateRoots[1]
    )
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $Members = @(Get-ChildItem `
            -LiteralPath $CandidateRoots[$Index] `
            -Force)
        Assert-BootstrapReleaseTest `
            -Condition (
                $Members.Count -eq 1 -and
                -not $Members[0].PSIsContainer -and
                [string]$Members[0].Name -ceq
                    [string]$Contracts[$Index].ProductBinary
            ) `
            -Message 'Candidate does not contain exactly one product binary'
    }

    $Arguments = @{
        Context = $Context
        CoreCandidateRoot = [string]$CoreCandidateRoot
        EntryCandidateRoot = [string]$EntryCandidateRoot
        EntryManagerCandidateRoots = $EntryManagerCandidateRoots
    }
    $First = Publish-SwawHarnessWindowsProducts @Arguments
    $FirstCreated = (Get-Item -LiteralPath $First.Root).CreationTimeUtc
    $Second = Publish-SwawHarnessWindowsProducts @Arguments
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
            $Selected.Artifacts.Count -eq 4 -and
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

    $IncompleteManagerRejected = $false
    try {
        [void](Publish-SwawHarnessWindowsProducts `
            -Context $Context `
            -CoreCandidateRoot ([string]$CoreCandidateRoot) `
            -EntryCandidateRoot ([string]$EntryCandidateRoot) `
            -EntryManagerCandidateRoots @(
                [string]$EntryManagerCandidateRoots[0]
            ))
    } catch {
        $IncompleteManagerRejected = $true
    }
    Assert-BootstrapReleaseTest `
        -Condition $IncompleteManagerRejected `
        -Message 'bundle publication accepted only one Entry Manager frontend'

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

    $CoreCandidateArtifact = Join-Path `
        $CoreCandidateRoot `
        $Contracts[0].ProductBinary
    $CandidateBytes = [IO.File]::ReadAllBytes($CoreCandidateArtifact)
    $CandidateBytes[0] = $CandidateBytes[0] -bxor 0xff
    [IO.File]::WriteAllBytes($CoreCandidateArtifact, $CandidateBytes)
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

    $LockedCandidateArtifact = Join-Path `
        $EntryCandidateRoot `
        $Contracts[1].ProductBinary
    $LockedCandidateStream = [IO.File]::Open(
        $LockedCandidateArtifact,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::None
    )
    try {
        $CleanupRecords = @(
            Clear-SwawHarnessWindowsProductCandidates -Context $Context 3>&1
        )
    } finally {
        $LockedCandidateStream.Dispose()
    }
    $CleanupWarnings = @($CleanupRecords | Where-Object {
        $_ -is [Management.Automation.WarningRecord]
    })
    Assert-BootstrapReleaseTest `
        -Condition (
            $CleanupWarnings.Count -ge 1 -and
            [IO.Directory]::Exists([string]$EntryCandidateRoot)
        ) `
        -Message 'Candidate cleanup failure was not reported as a warning'

    Clear-SwawHarnessWindowsProductCandidates -Context $Context
    $RemainingCandidateRoots = @($CandidateRoots | Where-Object {
        Test-SwawHarnessPathExists -Path $_
    })
    Assert-BootstrapReleaseTest `
        -Condition ($RemainingCandidateRoots.Count -eq 0) `
        -Message 'a later Candidate cleanup did not remove stale members'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap bundle Release' -ForegroundColor Green
