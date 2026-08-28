[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'toolchain\lifecycle.ps1')

if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\data'))
}
$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
[void](Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..'))
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
Write-Output (Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $Contract)
