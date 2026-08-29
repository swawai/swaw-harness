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

$Toolchain = Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $PlatformContract
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $Context `
    -Contract $PlatformContract `
    -Toolchain $Toolchain
$LifecycleLock = Enter-SwawHarnessFileLock `
    -Path (Join-Path $Context.LockRoot (
        "bootstrap-$($PlatformContract.PlatformTargetId).lock"
    )) `
    -ControlledRoot $Context.DataRepo `
    -TimeoutSeconds 7200
try {
    $CoreBuildResults = @(& (Join-Path $PSScriptRoot 'core\build.ps1') `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
    if ($CoreBuildResults.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$CoreBuildResults[0])) {
        throw 'Core build must return exactly one immutable Candidate root.'
    }
    $EntryBuildResults = @(& (Join-Path $PSScriptRoot 'entry\build.ps1') `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
    if ($EntryBuildResults.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$EntryBuildResults[0])) {
        throw 'Entry executable build must return one immutable Candidate root.'
    }
    $EntryManagerBuildResults = @(
        & (Join-Path $PSScriptRoot 'entry.manager\build.ps1') `
            -CargoPath $Plan.CargoPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    if ($EntryManagerBuildResults.Count -ne 2 -or
        @($EntryManagerBuildResults | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_)
        }).Count -ne 0) {
        throw 'Entry Manager build must return two immutable Candidate roots.'
    }

    $PublicationResults = @(Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidateRoot ([string]$CoreBuildResults[0]) `
        -EntryCandidateRoot ([string]$EntryBuildResults[0]) `
        -EntryManagerCandidateRoots @(
            [string]$EntryManagerBuildResults[0],
            [string]$EntryManagerBuildResults[1]
        ))
    if ($PublicationResults.Count -ne 1) {
        throw 'Bootstrap publication must return exactly one Release.'
    }
    Clear-SwawHarnessWindowsProductCandidates -Context $Context
    Write-Output $PublicationResults[0]
} finally {
    $LifecycleLock.Dispose()
}
