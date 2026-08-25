Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\..\builder\process.ps1')
. (Join-Path $PSScriptRoot 'definition.ps1')

function Get-SwawHarnessRustProcessEnvironment {
    param([Parameter(Mandatory = $true)][string]$RustRoot)

    return [ordered]@{
        CARGO_HOME = Join-Path $RustRoot 'cargo'
        RUSTUP_HOME = Join-Path $RustRoot 'rustup'
        RUSTUP_TERM_COLOR = 'never'
    }
}

function Invoke-SwawHarnessRustupInstaller {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$RustRoot
    )

    foreach ($RelativeRoot in @('cargo', 'rustup')) {
        $Root = Join-Path $RustRoot $RelativeRoot
        if (-not [IO.Directory]::Exists($Root)) {
            throw "Rust staging directory is missing: $Root"
        }
        $Unexpected = [IO.Directory]::EnumerateFileSystemEntries($Root) |
            Select-Object -First 1
        if ($null -ne $Unexpected) {
            throw "Rust staging root is not clean: $Unexpected"
        }
    }
    $Environment = Get-SwawHarnessRustProcessEnvironment -RustRoot $RustRoot
    $Environment['RUSTUP_INIT_SKIP_EXISTENCE_CHECKS'] = 'yes'
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $InstallerPath `
        -Arguments @(
            '-y',
            '--default-host', [string]$Contract.TargetId,
            '--no-modify-path',
            '--profile', [string]$Contract.RustProfile,
            '--default-toolchain', [string]$Contract.RustToolchain
        ) `
        -WorkingDirectory $RustRoot `
        -EnvironmentVariables $Environment `
        -UnsetEnvironmentVariables (
            Get-SwawHarnessRustAmbientOverrideNames
        ) `
        -TimeoutSeconds 1800
    if ($Result.ExitCode -ne 0) {
        throw (
            "rustup-init exited with code $($Result.ExitCode). " +
            "$($Result.Error) $($Result.Output)"
        ).Trim()
    }
}

function Get-SwawHarnessRustProbe {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RustRoot
    )

    $Rustup = Join-Path $RustRoot 'cargo\bin\rustup.exe'
    [void](Get-Item -LiteralPath $Rustup -Force -ErrorAction Stop)
    $Environment = Get-SwawHarnessRustProcessEnvironment -RustRoot $RustRoot
    $Unset = Get-SwawHarnessRustAmbientOverrideNames
    $ToolchainName = Get-SwawHarnessRustToolchainName -Contract $Contract
    $RustupResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $Rustup `
        -Arguments @('--version') `
        -WorkingDirectory $RustRoot `
        -EnvironmentVariables $Environment `
        -UnsetEnvironmentVariables $Unset
    $RustcResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $Rustup `
        -Arguments @('run', $ToolchainName, 'rustc', '-Vv') `
        -WorkingDirectory $RustRoot `
        -EnvironmentVariables $Environment `
        -UnsetEnvironmentVariables $Unset
    $CargoResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $Rustup `
        -Arguments @('run', $ToolchainName, 'cargo', '--version') `
        -WorkingDirectory $RustRoot `
        -EnvironmentVariables $Environment `
        -UnsetEnvironmentVariables $Unset
    foreach ($Result in @($RustupResult, $RustcResult, $CargoResult)) {
        if ($Result.ExitCode -ne 0) {
            throw "Rust installation probe failed: $($Result.Error)"
        }
    }

    $RustupMatch = [regex]::Match(
        $RustupResult.Output,
        '(?m)^rustup\s+(\d+\.\d+\.\d+(?:\S*)?)'
    )
    $ReleaseMatch = [regex]::Match(
        $RustcResult.Output,
        '(?m)^release:\s+(\S+)\s*$'
    )
    $CommitMatch = [regex]::Match(
        $RustcResult.Output,
        '(?m)^commit-hash:\s+([a-f0-9]{40})\s*$'
    )
    $HostMatch = [regex]::Match(
        $RustcResult.Output,
        '(?m)^host:\s+(\S+)\s*$'
    )
    $CargoMatch = [regex]::Match(
        $CargoResult.Output,
        '(?m)^cargo\s+(\d+\.\d+\.\d+(?:\S*)?)'
    )
    if (-not $RustupMatch.Success -or
        -not $ReleaseMatch.Success -or
        -not $CommitMatch.Success -or
        -not $HostMatch.Success -or
        -not $CargoMatch.Success -or
        $RustupMatch.Groups[1].Value -cne
            [string]$Contract.RustupInitVersion -or
        $ReleaseMatch.Groups[1].Value -cne
            [string]$Contract.RustToolchain -or
        $HostMatch.Groups[1].Value -cne [string]$Contract.TargetId) {
        throw 'The installed Rust toolchain reported an unexpected identity.'
    }
    return [pscustomobject][ordered]@{
        rustupVersion = $RustupMatch.Groups[1].Value
        rustcVersion = $ReleaseMatch.Groups[1].Value
        rustcCommit = $CommitMatch.Groups[1].Value
        cargoVersion = $CargoMatch.Groups[1].Value
        host = $HostMatch.Groups[1].Value
    }
}
