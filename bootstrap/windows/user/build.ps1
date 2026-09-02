[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CompilerPath,
    [Parameter(Mandatory = $true)][string]$LinkerPath,
    [Collections.IDictionary]$EnvironmentVariables = @{},
    [string[]]$UnsetEnvironmentVariables = @(),
    [IO.FileStream]$CandidateLifecycleLock = $null
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'candidate-build.ps1')

$RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..\..')
$Context = New-SwawHarnessWindowsBootstrapContext `
    -DataRepo (Join-Path $RepositoryRoot 'data.repo')
Invoke-SwawHarnessWindowsUserCliCandidateBuild `
    -Context $Context `
    -CompilerPath $CompilerPath `
    -LinkerPath $LinkerPath `
    -EnvironmentVariables $EnvironmentVariables `
    -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
    -CandidateLifecycleLock $CandidateLifecycleLock
