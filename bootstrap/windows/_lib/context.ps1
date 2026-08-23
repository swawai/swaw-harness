Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')

function New-SwawHarnessWindowsBootstrapContext {
    param([Parameter(Mandatory = $true)][string]$VarRoot)

    Assert-SwawHarnessWindowsX64
    $VarRoot = Assert-SwawHarnessControlledRoot `
        -Root $VarRoot `
        -Description 'VarRoot'
    [void][IO.Directory]::CreateDirectory($VarRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $VarRoot `
        -Description 'VarRoot')

    $CacheRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $VarRoot 'var_cache') `
        -Root $VarRoot `
        -Activity 'using var_cache'
    [void][IO.Directory]::CreateDirectory($CacheRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $CacheRoot `
        -Description 'var_cache')

    $BootstrapRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $CacheRoot 'bootstrap\windows') `
        -Root $CacheRoot `
        -Activity 'using the Windows Bootstrap cache'
    [void][IO.Directory]::CreateDirectory($BootstrapRoot)

    return [pscustomobject][ordered]@{
        VarRoot = $VarRoot
        CacheRoot = $CacheRoot
        BootstrapRoot = $BootstrapRoot
        DownloadRoot = Join-Path $BootstrapRoot 'downloads'
        ToolchainRoot = Join-Path $BootstrapRoot 'toolchains'
        WorkRoot = Join-Path $BootstrapRoot 'work'
        CargoHome = Join-Path $BootstrapRoot 'cargo'
        LockRoot = Join-Path $BootstrapRoot 'locks'
        LogRoot = Join-Path $BootstrapRoot 'logs'
    }
}
