Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')

function New-SwawHarnessWindowsBootstrapContext {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    Assert-SwawHarnessWindowsX64
    $DataRoot = Assert-SwawHarnessControlledRoot `
        -Root $DataRoot `
        -Description 'DataRoot'
    [void][IO.Directory]::CreateDirectory($DataRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $DataRoot `
        -Description 'DataRoot')

    $BootstrapWindowsRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $DataRoot 'bootstrap.windows') `
        -Root $DataRoot `
        -Activity 'using Windows Bootstrap state'
    [void][IO.Directory]::CreateDirectory($BootstrapWindowsRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $BootstrapWindowsRoot `
        -Description 'BootstrapWindowsRoot')

    $BootstrapWindowsCacheRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $DataRoot 'bootstrap.windows.cache') `
        -Root $DataRoot `
        -Activity 'using Windows Bootstrap cache'
    [void][IO.Directory]::CreateDirectory($BootstrapWindowsCacheRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $BootstrapWindowsCacheRoot `
        -Description 'BootstrapWindowsCacheRoot')

    $NativeRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $DataRoot 'n') `
        -Root $DataRoot `
        -Activity 'using Windows Bootstrap native data'
    [void][IO.Directory]::CreateDirectory($NativeRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $NativeRoot `
        -Description 'NativeRoot')

    return [pscustomobject][ordered]@{
        DataRoot = $DataRoot
        BootstrapWindowsRoot = $BootstrapWindowsRoot
        BootstrapWindowsCacheRoot = $BootstrapWindowsCacheRoot
        NativeRoot = $NativeRoot
        NativeInstallRoot = Join-Path $DataRoot 'i'
        BootstrapReleaseRoot = Join-Path $DataRoot 'bootstrap.release'
        DownloadRoot = Join-Path $BootstrapWindowsCacheRoot 'downloads'
        ToolchainRoot = Join-Path $NativeRoot 't'
        WorkRoot = Join-Path $NativeRoot 'w'
        NativeBuildRoot = Join-Path $NativeRoot 'b'
        CargoHome = Join-Path $NativeRoot 'c'
        LockRoot = Join-Path $BootstrapWindowsRoot 'locks'
        LogRoot = Join-Path $BootstrapWindowsRoot 'logs'
    }
}
