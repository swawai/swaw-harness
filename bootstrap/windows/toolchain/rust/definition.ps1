Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\..\builder\foundation.ps1')

$script:SwawHarnessRustRecipeVersion = '3'

function Get-SwawHarnessRustAmbientOverrideNames {
    return [string[]]@(
        'RUSTUP_TOOLCHAIN'
        'RUSTUP_TOOLCHAIN_SOURCE'
        'RUSTUP_DIST_SERVER'
        'RUSTUP_DIST_ROOT'
        'RUSTUP_UPDATE_ROOT'
        'RUSTUP_VERSION'
        'RUSTUP_INIT_SKIP_PATH_CHECK'
    )
}

function Get-SwawHarnessRustToolchainName {
    param([Parameter(Mandatory = $true)][object]$Contract)

    return "$($Contract.RustToolchain)-$($Contract.PlatformTargetId)"
}

function Get-SwawHarnessRustDefinitionId {
    param([Parameter(Mandatory = $true)][object]$Contract)

    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        'swaw.harness.bootstrap.rust-definition/v1'
        "recipe=$script:SwawHarnessRustRecipeVersion"
        "target=$($Contract.PlatformTargetId)"
        "toolchain=$($Contract.RustToolchain)"
        "profile=$($Contract.RustProfile)"
        "components=$([string]::Join(',', $Contract.RustComponents))"
        "rustupVersion=$($Contract.RustupInitVersion)"
        "rustupUrl=$($Contract.RustupInitUrl)"
        "rustupLength=$($Contract.RustupInitLength)"
        "rustupSha256=$($Contract.RustupInitSha256)"
    )))
}

function Get-SwawHarnessRustRequiredPaths {
    param([Parameter(Mandatory = $true)][object]$Contract)

    $RequiredPaths = [Collections.Generic.List[string]]::new()
    foreach ($Path in @(
        'bin\rustc.exe'
        'bin\cargo.exe'
        'bin\rustdoc.exe'
        (
            'lib\rustlib\' +
            "manifest-rust-std-$($Contract.PlatformTargetId)"
        )
    )) {
        $RequiredPaths.Add($Path)
    }
    foreach ($Component in [string[]]@($Contract.RustComponents)) {
        switch -CaseSensitive ($Component) {
            'clippy' {
                $RequiredPaths.Add('bin\cargo-clippy.exe')
                $RequiredPaths.Add('bin\clippy-driver.exe')
            }
            'rustfmt' {
                $RequiredPaths.Add('bin\cargo-fmt.exe')
                $RequiredPaths.Add('bin\rustfmt.exe')
            }
            default {
                throw "Unsupported managed Rust component: $Component"
            }
        }
    }
    return $RequiredPaths.ToArray()
}
