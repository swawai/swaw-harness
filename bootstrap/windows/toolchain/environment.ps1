Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'rust\definition.ps1')

function Assert-SwawHarnessToolchainDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Path = Get-SwawHarnessFullPath -Path $Path
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item -or -not $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must be a regular directory: $Path"
    }
    return $Path
}

function Get-SwawHarnessToolchainEnvironment {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$Toolchain
    )

    [void](Assert-SwawHarnessNativeTreePathBudget `
        -Root ([string]$Toolchain.Root) `
        -Description 'Managed toolchain path')
    $RustRoot = Assert-SwawHarnessPathInsideRoot `
        -Path ([string]$Toolchain.RustRoot) `
        -Root $Context.ToolchainRoot `
        -Activity 'preparing the Rust build environment'
    $MsvcRoot = Assert-SwawHarnessPathInsideRoot `
        -Path ([string]$Toolchain.MsvcRoot) `
        -Root $Context.ToolchainRoot `
        -Activity 'preparing the MSVC build environment'
    $ToolVersion = [string]$Toolchain.Metadata.msvc.toolVersion
    $SdkVersion = [string]$Toolchain.Metadata.msvc.sdkVersion
    $RustBin = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $RustRoot 'bin') `
        -Description 'Rust toolchain bin'
    $CargoHome = Assert-SwawHarnessPathInsideRoot `
        -Path $Context.CargoHome `
        -Root $Context.CacheRoot `
        -Activity 'using the mutable Cargo cache'
    [void][IO.Directory]::CreateDirectory($CargoHome)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $CargoHome `
        -Description 'Cargo cache')

    $VcRoot = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $MsvcRoot 'VC') `
        -Description 'MSVC VC root'
    $ToolRoot = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $VcRoot "Tools\MSVC\$ToolVersion") `
        -Description 'MSVC tool root'
    $SdkRoot = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $MsvcRoot 'Windows Kits\10') `
        -Description 'Windows SDK root'
    $ToolBin = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $ToolRoot 'bin\Hostx64\x64') `
        -Description 'MSVC x64 bin'
    $SdkBin = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $SdkRoot "bin\$SdkVersion\x64") `
        -Description 'Windows SDK x64 bin'
    $SdkUcrtBin = Assert-SwawHarnessToolchainDirectory `
        -Path (Join-Path $SdkBin 'ucrt') `
        -Description 'Windows SDK UCRT bin'

    $IncludePaths = [string[]]@(
        (Join-Path $ToolRoot 'include')
        (Join-Path $SdkRoot "Include\$SdkVersion\ucrt")
        (Join-Path $SdkRoot "Include\$SdkVersion\shared")
        (Join-Path $SdkRoot "Include\$SdkVersion\um")
        (Join-Path $SdkRoot "Include\$SdkVersion\winrt")
        (Join-Path $SdkRoot "Include\$SdkVersion\cppwinrt")
    )
    $LibPaths = [string[]]@(
        (Join-Path $ToolRoot 'lib\x64')
        (Join-Path $SdkRoot "Lib\$SdkVersion\ucrt\x64")
        (Join-Path $SdkRoot "Lib\$SdkVersion\um\x64")
    )
    foreach ($Directory in @($IncludePaths + $LibPaths)) {
        [void](Assert-SwawHarnessToolchainDirectory `
            -Path $Directory `
            -Description 'compiler search directory')
    }

    $CargoPath = Join-Path $RustBin 'cargo.exe'
    $RustcPath = Join-Path $RustBin 'rustc.exe'
    $RustdocPath = Join-Path $RustBin 'rustdoc.exe'
    $CompilerPath = Join-Path $ToolBin 'cl.exe'
    $LinkerPath = Join-Path $ToolBin 'link.exe'
    $LibrarianPath = Join-Path $ToolBin 'lib.exe'
    $ResourceCompilerPath = Join-Path $SdkBin 'rc.exe'
    foreach ($Executable in @(
        $CargoPath, $RustcPath, $RustdocPath,
        $CompilerPath, $LinkerPath, $LibrarianPath, $ResourceCompilerPath
    )) {
        [void](Assert-SwawHarnessRegularFile `
            -Path $Executable `
            -Description 'managed toolchain executable')
    }

    $EnvironmentVariables = [ordered]@{
        VSCMD_ARG_HOST_ARCH = 'x64'
        VSCMD_ARG_TGT_ARCH = 'x64'
        VCToolsVersion = $ToolVersion
        WindowsSDKVersion = "$SdkVersion\"
        VCToolsInstallDir = "$ToolRoot\"
        VCINSTALLDIR = "$VcRoot\"
        WindowsSdkDir = "$SdkRoot\"
        WindowsSdkBinPath = "$SdkRoot\bin\"
        WindowsSdkVerBinPath = "$SdkBin\"
        UniversalCRTSdkDir = "$SdkRoot\"
        UCRTVersion = $SdkVersion
        INCLUDE = [string]::Join(';', $IncludePaths)
        LIB = [string]::Join(';', $LibPaths)
        CARGO_HOME = $CargoHome
        RUSTC = $RustcPath
        RUSTDOC = $RustdocPath
        CARGO_BUILD_RUSTC = $RustcPath
        CARGO_BUILD_RUSTDOC = $RustdocPath
        CARGO_TERM_COLOR = 'never'
        CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = $LinkerPath
    }
    $PathPrefixes = [string[]]@(
        $ToolBin, $SdkBin, $SdkUcrtBin, $RustBin
    )
    $CurrentPath = [Environment]::GetEnvironmentVariable(
        'Path',
        [EnvironmentVariableTarget]::Process
    )
    $PathParts = [Collections.Generic.List[string]]::new()
    foreach ($Prefix in $PathPrefixes) {
        $PathParts.Add($Prefix)
    }
    if (-not [string]::IsNullOrWhiteSpace($CurrentPath)) {
        $PathParts.Add($CurrentPath)
    }
    $EnvironmentVariables['Path'] = [string]::Join(
        [IO.Path]::PathSeparator,
        $PathParts.ToArray()
    )

    $UnsetNames = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($Name in @(
        'CL', '_CL_', 'LINK', '_LINK_', 'RUSTFLAGS', 'RUSTDOCFLAGS',
        'CARGO_ENCODED_RUSTFLAGS', 'RUSTC_WRAPPER',
        'RUSTC_WORKSPACE_WRAPPER', 'CARGO_BUILD_TARGET', 'CARGO_TARGET_DIR'
    )) {
        [void]$UnsetNames.Add($Name)
    }
    foreach ($Name in Get-SwawHarnessRustAmbientOverrideNames) {
        [void]$UnsetNames.Add($Name)
    }
    return [pscustomobject][ordered]@{
        EnvironmentVariables = $EnvironmentVariables
        UnsetEnvironmentVariables = [string[]]@($UnsetNames)
        CargoPath = $CargoPath
        CompilerPath = $CompilerPath
        LinkerPath = $LinkerPath
        LibrarianPath = $LibrarianPath
        ResourceCompilerPath = $ResourceCompilerPath
        RustcPath = $RustcPath
        RustdocPath = $RustdocPath
    }
}
