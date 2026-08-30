[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'publication.ps1')

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
$RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..')
$Context = New-SwawHarnessWindowsBootstrapContext `
    -DataRepo (Join-Path $RepositoryRoot 'data.repo')
$CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
    -Path (Join-Path $PSScriptRoot 'core\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId)

$Toolchain = Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $PlatformContract
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $Context `
    -Contract $PlatformContract `
    -Toolchain $Toolchain
$LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
    -Context $Context `
    -PlatformTargetId $PlatformContract.PlatformTargetId
try {
    $CoreBuildResults = @(& (Join-Path $PSScriptRoot 'core\build.ps1') `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -CandidateLifecycleLock $LifecycleLock.Stream)
    if ($CoreBuildResults.Count -ne $CoreContracts.Count -or
        @($CoreBuildResults | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_)
        }).Count -ne 0) {
        throw 'Core build must return every immutable Candidate root.'
    }
    $EntryBuildResults = @(& (Join-Path $PSScriptRoot 'entry\build.ps1') `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -CandidateLifecycleLock $LifecycleLock.Stream)
    if ($EntryBuildResults.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$EntryBuildResults[0])) {
        throw 'Entry executable build must return one immutable Candidate root.'
    }
    $EntryManagerBuildResults = @(
        & (Join-Path $PSScriptRoot 'entry.manager\build.ps1') `
            -CargoPath $Plan.CargoPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
            -CandidateLifecycleLock $LifecycleLock.Stream
    )
    if ($EntryManagerBuildResults.Count -ne 2 -or
        @($EntryManagerBuildResults | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_)
        }).Count -ne 0) {
        throw 'Entry Manager build must return two immutable Candidate roots.'
    }

    $PublicationResults = @(Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidateRoots ([string[]]$CoreBuildResults) `
        -EntryCandidateRoot ([string]$EntryBuildResults[0]) `
        -EntryManagerCandidateRoots @(
            [string]$EntryManagerBuildResults[0],
            [string]$EntryManagerBuildResults[1]
        ) `
        -CandidateLifecycleLock $LifecycleLock.Stream)
    if ($PublicationResults.Count -ne 1) {
        throw 'Bootstrap publication must return exactly one Release.'
    }
    Clear-SwawHarnessWindowsProductCandidates `
        -Context $Context `
        -CandidateLifecycleLock $LifecycleLock.Stream
    Write-Output $PublicationResults[0]
} finally {
    Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
}
