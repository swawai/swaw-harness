[CmdletBinding()]
param([string]$RepositoryDataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'toolchain\lifecycle.ps1')

if ([string]::IsNullOrWhiteSpace($RepositoryDataRoot)) {
    $RepositoryDataRoot = [IO.Path]::GetFullPath((
        Join-Path $PSScriptRoot '..\..\data.repo'
    ))
}
$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
[void](Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..'))
$Context = New-SwawHarnessWindowsBootstrapContext -RepositoryDataRoot $RepositoryDataRoot
Write-Output (Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $Contract)
