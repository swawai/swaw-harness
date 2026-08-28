[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ToolchainCommandTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Toolchain command test failed: $Message"
    }
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\process.ps1')
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$Before = [Environment]::GetEnvironmentVariable('RUSTFLAGS', 'Process')
[Environment]::SetEnvironmentVariable('RUSTFLAGS', 'ambient-test', 'Process')
try {
    $Setup = @(& (Join-Path $WindowsRoot 'toolchain-setup.ps1') `
        -DataRepo $DataRepo)
    Assert-ToolchainCommandTest `
        -Condition ($Setup.Count -eq 1 -and
            [IO.Directory]::Exists([string]$Setup[0].Root)) `
        -Message 'setup command did not return one valid toolchain'
    $Success = Invoke-SwawHarnessCapturedProcess `
        -Executable ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) `
        -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $WindowsRoot 'toolchain.ps1'),
            '-DataRepo', $DataRepo,
            'cargo', '--version'
        ) `
        -WorkingDirectory $DataRepo `
        -TimeoutSeconds 60
    Assert-ToolchainCommandTest `
        -Condition ($Success.ExitCode -eq 0 -and
            $Success.Output -cmatch '^cargo [0-9]') `
        -Message 'tool command did not preserve Cargo success semantics'
    $Failure = Invoke-SwawHarnessCapturedProcess `
        -Executable ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) `
        -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $WindowsRoot 'toolchain.ps1'),
            '-DataRepo', $DataRepo,
            'cargo', 'metadata',
            '--manifest-path', 'Z:\definitely-missing\Cargo.toml',
            '--format-version', '1'
        ) `
        -WorkingDirectory $DataRepo `
        -TimeoutSeconds 60
    Assert-ToolchainCommandTest `
        -Condition ($Failure.ExitCode -eq 101 -and
            $Failure.Error -notlike '*Exception:*') `
        -Message 'tool command did not preserve Cargo failure semantics'
    Assert-ToolchainCommandTest `
        -Condition (
            [Environment]::GetEnvironmentVariable(
                'RUSTFLAGS',
                'Process'
            ) -ceq 'ambient-test'
        ) `
        -Message 'tool command failed or mutated its parent environment'
} finally {
    [Environment]::SetEnvironmentVariable('RUSTFLAGS', $Before, 'Process')
}

Write-Host '[PASS] Windows Bootstrap toolchain commands' -ForegroundColor Green
