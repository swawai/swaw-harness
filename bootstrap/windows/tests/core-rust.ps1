[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
$SetupResults = @(& (Join-Path $WindowsRoot 'toolchain-setup.ps1'))
if ($SetupResults.Count -ne 1 -or
    -not [IO.Directory]::Exists([string]$SetupResults[0].Root)) {
    throw 'Core Rust tests require one valid controlled toolchain.'
}

$WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
$CargoTargetRoot = Join-Path $Context.BuildRoot 'core-test'
$RustTargetConfiguration = (
    "target.$($PlatformContract.PlatformTargetId).rustflags=" +
    '["-C","target-feature=+crt-static"]'
)
$PowerShellPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$Result = Invoke-SwawHarnessCapturedProcess `
    -Executable $PowerShellPath `
    -Arguments @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $WindowsRoot 'toolchain.ps1'),
        'cargo',
        '--config', $RustTargetConfiguration,
        'test',
        '--workspace',
        '--locked',
        '--manifest-path', $WorkspaceManifest,
        '--target', $PlatformContract.PlatformTargetId,
        '--target-dir', $CargoTargetRoot
    ) `
    -WorkingDirectory (Join-Path $RepositoryRoot 'core') `
    -TimeoutSeconds 1800
if ($Result.ExitCode -ne 0) {
    throw (
        "Core Cargo tests failed with exit code $($Result.ExitCode). " +
        "$($Result.Error) $($Result.Output)"
    ).Trim()
}

Write-Host '[PASS] Core Rust workspace tests' -ForegroundColor Green
