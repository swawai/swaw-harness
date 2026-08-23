[CmdletBinding()]
param([string]$VarRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '_lib\context.ps1')
. (Join-Path $PSScriptRoot '_lib\contract.ps1')
. (Join-Path $PSScriptRoot '_lib\toolchain\lifecycle.ps1')

if ([string]::IsNullOrWhiteSpace($VarRoot)) {
    $VarRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}
$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
$Context = New-SwawHarnessWindowsBootstrapContext -VarRoot $VarRoot
Write-Output (Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $Contract)
