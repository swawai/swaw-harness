[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'builder\process.ps1')
. (Join-Path $PSScriptRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'publication.ps1')
. (Join-Path $PSScriptRoot 'module-publication.ps1')
. (Join-Path $PSScriptRoot 'admin-initialization.ps1')

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
$RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..')
$Context = New-SwawHarnessWindowsBootstrapContext `
    -DataRepo (Join-Path $RepositoryRoot 'data.repo')
$CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
    -Path (Join-Path $PSScriptRoot 'core\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId)
$HostContract = Read-SwawHarnessWindowsCoreHostContract `
    -Path (Join-Path $PSScriptRoot 'host\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId
$StartupModuleContracts = @($CoreContracts; $HostContract)

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
    $CoreHostBuildResults = @(& (Join-Path $PSScriptRoot 'host\build.ps1') `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -CandidateLifecycleLock $LifecycleLock.Stream)
    if ($CoreHostBuildResults.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$CoreHostBuildResults[0])) {
        throw 'Core Host build must return one immutable Candidate root.'
    }
    $UserCliBuildResults = @(& (Join-Path $PSScriptRoot 'user\build.ps1') `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -CandidateLifecycleLock $LifecycleLock.Stream)
    if ($UserCliBuildResults.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$UserCliBuildResults[0])) {
        throw 'User CLI executable build must return one immutable Candidate root.'
    }
    $PublicationResults = @(Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidateRoots ([string[]]$CoreBuildResults) `
        -CoreHostCandidateRoot ([string]$CoreHostBuildResults[0]) `
        -UserCliCandidateRoot ([string]$UserCliBuildResults[0]) `
        -CandidateLifecycleLock $LifecycleLock.Stream)
    if ($PublicationResults.Count -ne 1) {
        throw 'Bootstrap publication must return exactly one Release.'
    }
    $Release = $PublicationResults[0]
    $ModuleReleases = @(Publish-SwawHarnessWindowsBootstrapModules `
        -Context $Context `
        -BootstrapRelease $Release)
    if ($ModuleReleases.Count -ne $StartupModuleContracts.Count) {
        throw 'Bootstrap must publish every startup Module Release.'
    }
    $HostModuleReleases = @($ModuleReleases | Where-Object {
        [string]$_.ModuleId -ceq $HostContract.ModuleId
    })
    if ($HostModuleReleases.Count -ne 1) {
        throw 'Bootstrap must publish exactly one Core Host Module Release.'
    }
    [void](Initialize-SwawHarnessWindowsAdmin `
        -Context $Context `
        -BootstrapRelease $Release `
        -HostModuleRelease $HostModuleReleases[0])
    Clear-SwawHarnessWindowsProductCandidates `
        -Context $Context `
        -CandidateLifecycleLock $LifecycleLock.Stream
    Write-Output $Release
} finally {
    Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
}
