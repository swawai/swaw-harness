Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\..\builder\filesystem.ps1')

function Get-SwawHarnessMsvcAssemblyVersions {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $InstallRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $InstallRoot `
        -Root $ControlledRoot `
        -Activity 'inspecting an MSVC installation'
    $RootItem = Get-Item `
        -LiteralPath $InstallRoot `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $RootItem -or -not $RootItem.PSIsContainer -or
        ($RootItem.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "MSVC installation root is invalid: $InstallRoot"
    }

    $VersionDirectories = {
        param([string]$Base, [string]$Description)

        if (-not [IO.Directory]::Exists($Base)) {
            return @()
        }
        return @(Get-ChildItem -LiteralPath $Base -Directory -Force |
            Where-Object {
                if (($_.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "$Description cannot contain a reparse point: $($_.FullName)"
                }
                $_.Name -match '^\d+(\.\d+)+$'
            } |
            Sort-Object { [version]$_.Name } -Descending)
    }
    $ToolDirs = @(& $VersionDirectories `
        (Join-Path $InstallRoot 'VC\Tools\MSVC') `
        'MSVC tool version directory')
    $SdkDirs = @(& $VersionDirectories `
        (Join-Path $InstallRoot 'Windows Kits\10\bin') `
        'Windows SDK version directory')
    if ($ToolDirs.Count -ne 1) {
        throw (
            'Expected one extracted x64 MSVC tool version; found ' +
            "$($ToolDirs.Count)."
        )
    }
    if ($SdkDirs.Count -ne 1) {
        throw (
            'Expected one extracted Windows SDK version; found ' +
            "$($SdkDirs.Count)."
        )
    }
    return [pscustomobject][ordered]@{
        ToolVersion = [string]$ToolDirs[0].Name
        SdkVersion = [string]$SdkDirs[0].Name
    }
}

function Remove-SwawHarnessMsvcOptionalPath {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $Path = Resolve-SwawHarnessChildPath `
        -Root $InstallRoot `
        -RelativePath $RelativePath `
        -Description 'MSVC cleanup path'
    if (Test-SwawHarnessPathExists -Path $Path) {
        Remove-SwawHarnessControlledPathWithRetry `
            -Path $Path `
            -ControlledRoot $ControlledRoot `
            -Activity 'cleaning an unused MSVC component'
    }
}

function Complete-SwawHarnessMsvcAssembly {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    $InstallRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $InstallRoot `
        -Root $Context.NativeRoot `
        -Activity 'completing an MSVC installation'
    $Versions = Get-SwawHarnessMsvcAssemblyVersions `
        -InstallRoot $InstallRoot `
        -ControlledRoot $Context.NativeRoot
    $ToolVersion = [string]$Versions.ToolVersion
    $SdkVersion = [string]$Versions.SdkVersion
    $DiaSource = Join-Path $InstallRoot 'DIA SDK\bin\amd64\msdia140.dll'
    $ToolBin = Join-Path $InstallRoot (
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64"
    )
    [void](Assert-SwawHarnessRegularFile `
        -Path $DiaSource `
        -Description 'x64 DIA runtime')
    [void][IO.Directory]::CreateDirectory($ToolBin)
    [IO.File]::Copy(
        $DiaSource,
        (Join-Path $ToolBin 'msdia140.dll'),
        $true
    )

    foreach ($RelativePath in @(
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\vctip.exe"
        'Common7'
        'Catalogs'
        'DesignTime'
        'Windows Kits\10\Catalogs'
        'Windows Kits\10\DesignTime'
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx86"
        "VC\Tools\MSVC\$ToolVersion\bin\Hostarm"
        "VC\Tools\MSVC\$ToolVersion\bin\Hostarm64"
    )) {
        Remove-SwawHarnessMsvcOptionalPath `
            -InstallRoot $InstallRoot `
            -ControlledRoot $Context.NativeRoot `
            -RelativePath $RelativePath
    }
    foreach ($Architecture in @('x86', 'arm', 'arm64')) {
        foreach ($RelativePath in @(
            "Windows Kits\10\bin\$SdkVersion\$Architecture"
            "Windows Kits\10\Lib\$SdkVersion\ucrt\$Architecture"
            "Windows Kits\10\Lib\$SdkVersion\um\$Architecture"
        )) {
            Remove-SwawHarnessMsvcOptionalPath `
                -InstallRoot $InstallRoot `
                -ControlledRoot $Context.NativeRoot `
                -RelativePath $RelativePath
        }
    }

    $BuildRoot = Join-Path $InstallRoot 'VC\Auxiliary\Build'
    [void][IO.Directory]::CreateDirectory($BuildRoot)
    [IO.File]::WriteAllText(
        (Join-Path $BuildRoot 'vcvarsall.bat'),
        "@echo off`r`nrem Compatibility marker for tools such as nvcc.`r`n",
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $BuildRoot 'vcvars64.bat'),
        "@echo off`r`ncall `"%~dp0..\..\..\setup_x64.bat`"`r`n",
        [Text.UTF8Encoding]::new($false)
    )
    $Setup = @(
        '@echo off'
        'set "VSCMD_ARG_HOST_ARCH=x64"'
        'set "VSCMD_ARG_TGT_ARCH=x64"'
        "set `"VCToolsVersion=$ToolVersion`""
        "set `"WindowsSDKVersion=$SdkVersion\`""
        "set `"VCToolsInstallDir=%~dp0VC\Tools\MSVC\$ToolVersion\`""
        'set "VCINSTALLDIR=%~dp0VC\"'
        'set "WindowsSdkDir=%~dp0Windows Kits\10\"'
        'set "WindowsSdkBinPath=%~dp0Windows Kits\10\bin\"'
        "set `"WindowsSdkVerBinPath=%~dp0Windows Kits\10\bin\$SdkVersion\x64\`""
        'set "UniversalCRTSdkDir=%~dp0Windows Kits\10\"'
        "set `"UCRTVersion=$SdkVersion`""
        (
            "set `"PATH=%~dp0VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64;" +
            "%~dp0Windows Kits\10\bin\$SdkVersion\x64;" +
            "%~dp0Windows Kits\10\bin\$SdkVersion\x64\ucrt;%PATH%`""
        )
        (
            "set `"INCLUDE=%~dp0VC\Tools\MSVC\$ToolVersion\include;" +
            "%~dp0Windows Kits\10\Include\$SdkVersion\ucrt;" +
            "%~dp0Windows Kits\10\Include\$SdkVersion\shared;" +
            "%~dp0Windows Kits\10\Include\$SdkVersion\um;" +
            "%~dp0Windows Kits\10\Include\$SdkVersion\winrt;" +
            "%~dp0Windows Kits\10\Include\$SdkVersion\cppwinrt`""
        )
        (
            "set `"LIB=%~dp0VC\Tools\MSVC\$ToolVersion\lib\x64;" +
            "%~dp0Windows Kits\10\Lib\$SdkVersion\ucrt\x64;" +
            "%~dp0Windows Kits\10\Lib\$SdkVersion\um\x64`""
        )
    )
    [IO.File]::WriteAllText(
        (Join-Path $InstallRoot 'setup_x64.bat'),
        ([string]::Join("`r`n", [string[]]$Setup) + "`r`n"),
        [Text.UTF8Encoding]::new($false)
    )
    return $Versions
}
