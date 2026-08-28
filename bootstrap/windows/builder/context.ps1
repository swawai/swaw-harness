Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')
. (Join-Path $PSScriptRoot 'filesystem.ps1')

function New-SwawHarnessWindowsBootstrapContext {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryDataRoot
    )

    Assert-SwawHarnessWindowsX64
    $RepositoryDataRoot = Assert-SwawHarnessControlledRoot `
        -Root $RepositoryDataRoot `
        -Description 'RepositoryDataRoot'
    [void][IO.Directory]::CreateDirectory($RepositoryDataRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $RepositoryDataRoot `
        -Description 'RepositoryDataRoot')

    $Roots = [ordered]@{
        BootstrapReleaseRoot = 'windows.release'
        BuildRoot = 'windows.build'
        ToolchainRoot = 'windows.tool'
        StageRoot = 'windows.stage'
        CacheRoot = 'windows.cache'
        LockRoot = 'windows.locks'
        LogRoot = 'windows.logs'
    }
    foreach ($Name in @($Roots.Keys)) {
        $Roots[$Name] = Assert-SwawHarnessPathInsideRoot `
            -Path (Join-Path $RepositoryDataRoot $Roots[$Name]) `
            -Root $RepositoryDataRoot `
            -Activity "using Windows Bootstrap $Name"
        if ([IO.Directory]::Exists($Roots[$Name])) {
            [void](Assert-SwawHarnessControlledRoot `
                -Root $Roots[$Name] `
                -Description $Name)
        } elseif (Test-SwawHarnessPathExists -Path $Roots[$Name]) {
            throw "$Name must be a regular directory: $($Roots[$Name])"
        }
    }

    return [pscustomobject][ordered]@{
        HarnessRoot = Split-Path -Path $RepositoryDataRoot -Parent
        RepositoryDataRoot = $RepositoryDataRoot
        BootstrapReleaseRoot = $Roots.BootstrapReleaseRoot
        BuildRoot = $Roots.BuildRoot
        ToolchainRoot = $Roots.ToolchainRoot
        StageRoot = $Roots.StageRoot
        CacheRoot = $Roots.CacheRoot
        LockRoot = $Roots.LockRoot
        LogRoot = $Roots.LogRoot
        RustupStageRoot = Join-Path $Roots.StageRoot 'rustup'
        CargoHome = Join-Path $Roots.CacheRoot 'cargo'
        DownloadRoot = Join-Path $Roots.CacheRoot 'downloads'
    }
}
