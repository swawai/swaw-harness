[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ControlledRoot,
    [Parameter(Mandatory = $true)][string]$RustRoot,
    [Parameter(Mandatory = $true)][string]$MsvcRoot,
    [Parameter(Mandatory = $true)][string]$RustRecordPath,
    [Parameter(Mandatory = $true)][string]$MsvcRecordPath,
    [Parameter(Mandatory = $true)][long]$RustupLength,
    [Parameter(Mandatory = $true)][string]$RustupSha256
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\rust\inventory.ps1')
. (Join-Path $WindowsRoot 'toolchain\msvc\inventory.ps1')

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$Contract.RustupInitLength = $RustupLength
$Contract.RustupInitSha256 = $RustupSha256
$RustRecord = Read-SwawHarnessJsonFile `
    -Path $RustRecordPath `
    -Description 'cross-runtime Rust record' `
    -MaximumBytes 32MB
$MsvcRecord = Read-SwawHarnessJsonFile `
    -Path $MsvcRecordPath `
    -Description 'cross-runtime MSVC record' `
    -MaximumBytes 32MB
[void](Test-SwawHarnessRustInstallRecord `
    -Record $RustRecord `
    -Contract $Contract `
    -RustRoot $RustRoot `
    -ControlledRoot $ControlledRoot `
    -Detailed)
[void](Test-SwawHarnessRustInstallRecord `
    -Record $RustRecord `
    -Contract $Contract `
    -RustRoot $RustRoot `
    -ControlledRoot $ControlledRoot `
    -Full `
    -Detailed)
[void](Test-SwawHarnessMsvcInstallRecord `
    -Record $MsvcRecord `
    -Contract $Contract `
    -MsvcRoot $MsvcRoot `
    -ControlledRoot $ControlledRoot `
    -Detailed)
[void](Test-SwawHarnessMsvcInstallRecord `
    -Record $MsvcRecord `
    -Contract $Contract `
    -MsvcRoot $MsvcRoot `
    -ControlledRoot $ControlledRoot `
    -Full `
    -Detailed)
Write-Host '[PASS] PowerShell 5.1 accepted PS7 inventories' -ForegroundColor Green
