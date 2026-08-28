[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$DataRoot = '',
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('cargo', 'rustc', 'rustdoc', 'cl', 'link', 'lib', 'rc')]
    [string]$Tool,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [AllowEmptyCollection()]
    [string[]]$ToolArguments = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'builder\process.ps1')

if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\data'))
}
$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
[void](Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot (Join-Path $PSScriptRoot '..\..'))
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$InstallRoot = Get-SwawHarnessToolchainTargetPath `
    -Context $Context `
    -Contract $Contract
$Toolchain = Get-SwawHarnessValidToolchain `
    -Context $Context `
    -Contract $Contract `
    -InstallRoot $InstallRoot
if ($null -eq $Toolchain) {
    throw (
        'The Contract toolchain is not installed or is invalid. Run ' +
        "'$PSScriptRoot\toolchain-setup.ps1' first."
    )
}
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $Context `
    -Contract $Contract `
    -Toolchain $Toolchain
$Executables = [ordered]@{
    cargo = [string]$Plan.CargoPath
    rustc = [string]$Plan.RustcPath
    rustdoc = [string]$Plan.RustdocPath
    cl = [string]$Plan.CompilerPath
    link = [string]$Plan.LinkerPath
    lib = [string]$Plan.LibrarianPath
    rc = [string]$Plan.ResourceCompilerPath
}
$Location = Get-Location
if ($null -eq $Location.Provider -or
    [string]$Location.Provider.Name -cne 'FileSystem') {
    throw 'Toolchain commands require a filesystem working directory.'
}
$ExitCode = Invoke-SwawHarnessInheritedProcess `
    -Executable ([string]$Executables[$Tool]) `
    -Arguments $ToolArguments `
    -WorkingDirectory ([IO.Path]::GetFullPath($Location.Path)) `
    -EnvironmentVariables $Plan.EnvironmentVariables `
    -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
    -TimeoutSeconds 1800
exit $ExitCode
