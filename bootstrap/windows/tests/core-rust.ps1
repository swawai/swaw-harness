[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')

if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'data'))
}
$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$SetupResults = @(& (Join-Path $WindowsRoot 'toolchain-setup.ps1') `
    -DataRoot $Context.DataRoot)
if ($SetupResults.Count -ne 1 -or
    -not [IO.Directory]::Exists([string]$SetupResults[0].Root)) {
    throw 'Core Rust tests require one valid controlled toolchain.'
}

$WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
$CargoTargetRoot = Join-Path $Context.BootstrapWindowsCacheRoot (
    "tests\core\$($PlatformContract.PlatformTargetId)\cargo-target"
)
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
        '-DataRoot', $Context.DataRoot,
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
