[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$VarRoot,
    [Parameter(Mandatory = $true)][string]$EntryRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '_lib\context.ps1')
. (Join-Path $PSScriptRoot '_lib\contract.ps1')
. (Join-Path $PSScriptRoot '_lib\release\selector.ps1')
. (Join-Path $PSScriptRoot '_lib\toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot '_lib\toolchain\environment.ps1')

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
$Context = New-SwawHarnessWindowsBootstrapContext -VarRoot $VarRoot
$EntrySpace = Assert-SwawHarnessPathInsideRoot `
    -Path (Join-Path $Context.VarRoot 'var_entry') `
    -Root $Context.VarRoot `
    -Activity 'using var_entry'
[void][IO.Directory]::CreateDirectory($EntrySpace)
[void](Assert-SwawHarnessControlledRoot `
    -Root $EntrySpace `
    -Description 'var_entry')
$EntryRoot = Get-SwawHarnessFullPath -Path $EntryRoot
if (-not (Split-Path -Path $EntryRoot -Parent).Equals(
    $EntrySpace,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "EntryRoot must be a direct child of var_entry: $EntryRoot"
}
[void](Assert-SwawHarnessPathInsideRoot `
    -Path $EntryRoot `
    -Root $EntrySpace `
    -Activity 'bootstrapping an Entry')
[void][IO.Directory]::CreateDirectory($EntryRoot)
[void](Assert-SwawHarnessControlledRoot `
    -Root $EntryRoot `
    -Description 'EntryRoot')

$Toolchain = Get-SwawHarnessBootstrapToolchain `
    -Context $Context `
    -Contract $Contract
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $Context `
    -Contract $Contract `
    -Toolchain $Toolchain
$BuildResults = @(& (Join-Path $PSScriptRoot 'build.ps1') `
    -VarRoot $Context.VarRoot `
    -CargoPath $Plan.CargoPath `
    -EnvironmentVariables $Plan.EnvironmentVariables `
    -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
if ($BuildResults.Count -ne 1 -or
    [string]::IsNullOrWhiteSpace([string]$BuildResults[0])) {
    throw 'Windows build must return exactly one immutable candidate path.'
}
$PublishResults = @(& (Join-Path $PSScriptRoot 'publish.ps1') `
    -VarRoot $Context.VarRoot `
    -EntryRoot $EntryRoot `
    -CandidatePath ([string]$BuildResults[0]))
if ($PublishResults.Count -ne 1) {
    throw 'Windows publish must return exactly one Release result.'
}
$Published = $PublishResults[0]
$Selected = Read-SwawHarnessSelectedRelease `
    -EntryRoot $EntryRoot `
    -Contract $Contract
if ([string]$Selected.ReleaseId -cne [string]$Published.ReleaseId) {
    throw 'Published Release does not match the selected Release.'
}
Write-Output $Selected
