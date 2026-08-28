[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RepositoryDataRoot)

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
$Context = New-SwawHarnessWindowsBootstrapContext -RepositoryDataRoot $RepositoryDataRoot

$Toolchain = Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $PlatformContract
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $Context `
    -Contract $PlatformContract `
    -Toolchain $Toolchain
$CoreBuildResults = @(& (Join-Path $PSScriptRoot 'core\build.ps1') `
    -RepositoryDataRoot $Context.RepositoryDataRoot `
    -CargoPath $Plan.CargoPath `
    -EnvironmentVariables $Plan.EnvironmentVariables `
    -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
if ($CoreBuildResults.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace([string]$CoreBuildResults[0])) {
    throw 'Core build must return exactly one immutable candidate path.'
}
$EntryBuildResults = @(& (Join-Path $PSScriptRoot 'entry\build.ps1') `
    -RepositoryDataRoot $Context.RepositoryDataRoot `
    -CompilerPath $Plan.CompilerPath `
    -LinkerPath $Plan.LinkerPath `
    -EnvironmentVariables $Plan.EnvironmentVariables `
    -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
if ($EntryBuildResults.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace([string]$EntryBuildResults[0])) {
    throw 'Entry executable build must return exactly one immutable candidate path.'
}
$EntryManagerBuildResults = @(& (Join-Path $PSScriptRoot 'entry.manager\build.ps1') `
    -RepositoryDataRoot $Context.RepositoryDataRoot `
    -CargoPath $Plan.CargoPath `
    -EnvironmentVariables $Plan.EnvironmentVariables `
    -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
if ($EntryManagerBuildResults.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace([string]$EntryManagerBuildResults[0])) {
    throw 'Entry Manager build must return exactly one immutable candidate path.'
}

$PublicationResults = @(Publish-SwawHarnessWindowsProducts `
    -RepositoryDataRoot $Context.RepositoryDataRoot `
    -CoreCandidatePath ([string]$CoreBuildResults[0]) `
    -EntryCandidatePath ([string]$EntryBuildResults[0]) `
    -EntryManagerCandidatePath ([string]$EntryManagerBuildResults[0]))
if ($PublicationResults.Count -ne 1) {
    throw 'Bootstrap publication must return exactly one Release.'
}
Write-Output $PublicationResults[0]
