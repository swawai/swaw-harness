Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\download-cache.ps1')
. (Join-Path $PSScriptRoot '..\..\builder\filesystem.ps1')
. (Join-Path $PSScriptRoot 'process.ps1')
. (Join-Path $PSScriptRoot 'inventory.ps1')

function Install-SwawHarnessRustIntoToolchainStage {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$StagedToolchainRoot,
        [Parameter(Mandatory = $true)][string]$RustInstallRoot
    )

    $RustRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $StagedToolchainRoot 'r') `
        -Root $Context.StageRoot `
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
    $RustInstallRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $RustInstallRoot `
        -Root $Context.StageRoot `
        -Activity 'installing a normalized Rust toolchain'
    $InstallLock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot 'rust-install.lock') `
        -ControlledRoot $Context.DataRepo `
        -TimeoutSeconds 1800
    try {
        if (Test-SwawHarnessPathExists -Path $RustInstallRoot) {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path $RustInstallRoot `
                -ControlledRoot $Context.StageRoot `
                -Activity 'cleaning interrupted Rust installation work'
        }
        [void][IO.Directory]::CreateDirectory(
            (Join-Path $RustInstallRoot 'c')
        )
        [void][IO.Directory]::CreateDirectory(
            (Join-Path $RustInstallRoot 'r')
        )

        Write-Host (
            "[STEP] Installing Rust $($Contract.RustToolchain) " +
            "($($Contract.RustProfile))..."
        ) -ForegroundColor Cyan
        Invoke-SwawHarnessRustupInstaller `
            -Contract $Contract `
            -InstallerPath $Installer `
            -RustRoot $RustInstallRoot
        $Probe = Get-SwawHarnessRustProbe `
            -Contract $Contract `
            -RustRoot $RustInstallRoot
        $ToolchainName = Get-SwawHarnessRustToolchainName -Contract $Contract
        $InstalledSysroot = Assert-SwawHarnessPathInsideRoot `
            -Path (Join-Path $RustInstallRoot "r\toolchains\$ToolchainName") `
            -Root $Context.StageRoot `
            -Activity 'normalizing the Rust sysroot'
        [void](Assert-SwawHarnessControlledRoot `
            -Root $InstalledSysroot `
            -Description 'installed Rust sysroot')
        Move-SwawHarnessControlledPathWithRetry `
            -Source $InstalledSysroot `
            -Destination $RustRoot `
            -ControlledRoot $Context.StageRoot `
            -Activity 'normalizing the Rust sysroot'
        $Record = New-SwawHarnessRustInstallRecord `
            -Contract $Contract `
            -Probe $Probe `
            -RustRoot $RustRoot `
            -ControlledRoot $Context.StageRoot
        if (-not (Test-SwawHarnessRustInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $Context.StageRoot `
            -Detailed
        )) {
            throw 'Staged Rust installation failed its receipt check.'
        }
        return $Record
    } finally {
        try {
            if (Test-SwawHarnessPathExists -Path $RustInstallRoot) {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path $RustInstallRoot `
                    -ControlledRoot $Context.StageRoot `
                    -Activity 'cleaning Rust installation work'
            }
        } finally {
            $InstallLock.Dispose()
        }
    }
}
