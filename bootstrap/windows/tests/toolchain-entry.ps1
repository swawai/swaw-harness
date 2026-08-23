[CmdletBinding()]
param([string]$VarRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ToolchainEntryTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Toolchain entry test failed: $Message"
    }
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot '_lib\process.ps1')
if ([string]::IsNullOrWhiteSpace($VarRoot)) {
    $VarRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
}
$Before = [Environment]::GetEnvironmentVariable('RUSTFLAGS', 'Process')
[Environment]::SetEnvironmentVariable('RUSTFLAGS', 'ambient-test', 'Process')
try {
    $Setup = @(& (Join-Path $WindowsRoot 'toolchain-setup.ps1') `
        -VarRoot $VarRoot)
    Assert-ToolchainEntryTest `
        -Condition ($Setup.Count -eq 1 -and
            [IO.Directory]::Exists([string]$Setup[0].Root)) `
        -Message 'setup entry did not return one valid toolchain'
    & (Join-Path $WindowsRoot 'toolchain.ps1') `
        -VarRoot $VarRoot `
        cargo `
        '--version'
    $Failure = Invoke-SwawHarnessCapturedProcess `
        -Executable ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) `
        -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $WindowsRoot 'toolchain.ps1'),
            '-VarRoot', $VarRoot,
            'cargo', 'metadata',
            '--manifest-path', 'Z:\definitely-missing\Cargo.toml',
            '--format-version', '1'
        ) `
        -WorkingDirectory $VarRoot `
        -TimeoutSeconds 60
    Assert-ToolchainEntryTest `
        -Condition ($Failure.ExitCode -eq 101 -and
            $Failure.Error -notlike '*Exception:*') `
        -Message 'tool entry did not preserve Cargo failure semantics'
    Assert-ToolchainEntryTest `
        -Condition (
            [Environment]::GetEnvironmentVariable(
                'RUSTFLAGS',
                'Process'
            ) -ceq 'ambient-test'
        ) `
        -Message 'tool entry failed or mutated its parent environment'
} finally {
    [Environment]::SetEnvironmentVariable('RUSTFLAGS', $Before, 'Process')
}

Write-Host '[PASS] Windows Bootstrap toolchain entries' -ForegroundColor Green
