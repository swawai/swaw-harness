[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CargoPath,
    [Collections.IDictionary]$EnvironmentVariables = @{},
    [string[]]$UnsetEnvironmentVariables = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'candidate-build.ps1')

$RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..\..')
$Context = New-SwawHarnessWindowsBootstrapContext `
    -DataRepo (Join-Path $RepositoryRoot 'data.repo')
Invoke-SwawHarnessWindowsCoreCandidateBuild `
    -Context $Context `
    -CargoPath $CargoPath `
    -EnvironmentVariables $EnvironmentVariables `
    -UnsetEnvironmentVariables $UnsetEnvironmentVariables
