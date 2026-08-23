Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\download-cache.ps1')
. (Join-Path $PSScriptRoot 'process.ps1')
. (Join-Path $PSScriptRoot 'inventory.ps1')

function Install-SwawHarnessRustIntoToolchainStage {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$StagedToolchainRoot
    )

    $RustRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $StagedToolchainRoot 'rust') `
        -Root $Context.CacheRoot `
        -Activity 'staging the Rust toolchain'
    if (Test-SwawHarnessPathExists -Path $RustRoot) {
        throw "Rust stage must not already exist: $RustRoot"
    }
    $Installer = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source ([string]$Contract.RustupInitUrl) `
        -ExpectedLength ([long]$Contract.RustupInitLength) `
        -ExpectedSha256 ([string]$Contract.RustupInitSha256) `
        -Description 'rustup-init executable'
    [void][IO.Directory]::CreateDirectory((Join-Path $RustRoot 'cargo'))
    [void][IO.Directory]::CreateDirectory((Join-Path $RustRoot 'rustup'))

    Write-Host (
        "[STEP] Installing Rust $($Contract.RustToolchain) " +
        "($($Contract.RustProfile))..."
    ) -ForegroundColor Cyan
    Invoke-SwawHarnessRustupInstaller `
        -Contract $Contract `
        -InstallerPath $Installer `
        -RustRoot $RustRoot
    $Probe = Get-SwawHarnessRustProbe `
        -Contract $Contract `
        -RustRoot $RustRoot
    $Record = New-SwawHarnessRustInstallRecord `
        -Contract $Contract `
        -Probe $Probe `
        -RustRoot $RustRoot `
        -ControlledRoot $Context.CacheRoot
    if (-not (Test-SwawHarnessRustInstallRecord `
        -Record $Record `
        -Contract $Contract `
        -RustRoot $RustRoot `
        -ControlledRoot $Context.CacheRoot `
        -Detailed
    )) {
        throw 'Staged Rust installation failed its receipt check.'
    }
    return $Record
}
