Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')

function Assert-SwawHarnessHttpsSource {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$ExpectedHost,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$Uri) -or
        $Uri.Scheme -cne 'https' -or $Uri.Host -cne $ExpectedHost) {
        throw "$Description must use HTTPS on $ExpectedHost."
    }
    return $Uri.AbsoluteUri
}

function Assert-SwawHarnessSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Normalized = $Value.Trim().ToLowerInvariant()
    if ($Normalized -cnotmatch '^[a-f0-9]{64}$') {
        throw "$Description must be a lowercase SHA-256 digest."
    }
    return $Normalized
}

function Read-SwawHarnessWindowsBootstrapContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Contract = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Windows Bootstrap contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract `
        -Expected @('schema', 'targetId', 'rust', 'msvc') `
        -Description 'Windows Bootstrap contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract.rust `
        -Expected @('toolchain', 'profile', 'rustupInit') `
        -Description 'Windows Bootstrap rust contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract.rust.rustupInit `
        -Expected @('version', 'url', 'length', 'sha256') `
        -Description 'Windows Bootstrap rustup-init contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract.msvc `
        -Expected @('productLine', 'license', 'manifest') `
        -Description 'Windows Bootstrap MSVC contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract.msvc.license `
        -Expected @('url', 'acceptance') `
        -Description 'Windows Bootstrap MSVC license contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract.msvc.manifest `
        -Expected @('url', 'length', 'sha256') `
        -Description 'Windows Bootstrap MSVC manifest contract'
    $TargetId = ([string]$Contract.targetId).Trim().ToLowerInvariant()
    $Toolchain = ([string]$Contract.rust.toolchain).Trim().ToLowerInvariant()
    $Profile = ([string]$Contract.rust.profile).Trim().ToLowerInvariant()
    $RustupVersion = ([string]$Contract.rust.rustupInit.version).
        Trim().ToLowerInvariant()
    $MsvcProductLine = ([string]$Contract.msvc.productLine).
        Trim().ToLowerInvariant()
    $MsvcLicenseAcceptance = ([string]$Contract.msvc.license.acceptance).
        Trim().ToLowerInvariant()
    if ([string]$Contract.schema -cne 'swaw.harness.bootstrap.windows/v3') {
        throw 'Unsupported Windows Bootstrap contract schema.'
    }
    if ($TargetId -cnotmatch '^[a-z0-9][a-z0-9._-]{0,127}$') {
        throw 'Windows Bootstrap targetId is invalid.'
    }
    if ($TargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows Bootstrap v3 supports x86_64-pc-windows-msvc only.'
    }
    if ($Toolchain -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'Windows Bootstrap rust.toolchain must be an exact version.'
    }
    if ($RustupVersion -cnotmatch '^\d+\.\d+\.\d+$') {
        throw 'Windows Bootstrap rustup-init version must be exact.'
    }
    if ($Profile -cne 'minimal') {
        throw 'Windows Bootstrap v3 requires the minimal Rust profile.'
    }
    if ($MsvcProductLine -cne 'vs2026') {
        throw 'Windows Bootstrap v3 requires the VS 2026 product line.'
    }
    if ($MsvcLicenseAcceptance -cne 'by-bootstrap-invocation') {
        throw 'Windows Bootstrap MSVC license acceptance is invalid.'
    }
    $RustupLength = [long]$Contract.rust.rustupInit.length
    $ManifestLength = [long]$Contract.msvc.manifest.length
    if ($RustupLength -le 0 -or $RustupLength -gt 512MB) {
        throw 'Windows Bootstrap rustup-init length is invalid.'
    }
    if ($ManifestLength -le 0 -or $ManifestLength -gt 64MB) {
        throw 'Windows Bootstrap MSVC manifest length is invalid.'
    }
    $RustupUrl = Assert-SwawHarnessHttpsSource `
        -Value ([string]$Contract.rust.rustupInit.url) `
        -ExpectedHost 'static.rust-lang.org' `
        -Description 'rustup-init source'
    $ExpectedRustupPath = (
        "/rustup/archive/$RustupVersion/$TargetId/rustup-init.exe"
    )
    if (([Uri]$RustupUrl).AbsolutePath -cne $ExpectedRustupPath) {
        throw 'rustup-init source does not match its version and target.'
    }
    $ManifestUrl = Assert-SwawHarnessHttpsSource `
        -Value ([string]$Contract.msvc.manifest.url) `
        -ExpectedHost 'download.visualstudio.microsoft.com' `
        -Description 'Visual Studio manifest source'
    if ([IO.Path]::GetFileName(([Uri]$ManifestUrl).AbsolutePath) -cne
        'VisualStudio.vsman') {
        throw 'Visual Studio manifest source has an unexpected file name.'
    }
    $LicenseUrl = Assert-SwawHarnessHttpsSource `
        -Value ([string]$Contract.msvc.license.url) `
        -ExpectedHost 'go.microsoft.com' `
        -Description 'Microsoft Build Tools license source'
    $LicenseUri = [Uri]$LicenseUrl
    if ($LicenseUri.AbsolutePath -cne '/fwlink/' -or
        $LicenseUri.Query -cne '?LinkId=2327714') {
        throw 'Microsoft Build Tools license source is unexpected.'
    }

    return [pscustomobject][ordered]@{
        Schema = [string]$Contract.schema
        TargetId = $TargetId
        RustToolchain = $Toolchain
        RustProfile = $Profile
        RustupInitVersion = $RustupVersion
        RustupInitUrl = $RustupUrl
        RustupInitSha256 = Assert-SwawHarnessSha256 `
            -Value ([string]$Contract.rust.rustupInit.sha256) `
            -Description 'rustup-init checksum'
        RustupInitLength = $RustupLength
        MsvcProductLine = $MsvcProductLine
        MsvcLicenseUrl = $LicenseUrl
        MsvcLicenseAcceptance = $MsvcLicenseAcceptance
        MsvcManifestUrl = $ManifestUrl
        MsvcManifestSha256 = Assert-SwawHarnessSha256 `
            -Value ([string]$Contract.msvc.manifest.sha256) `
            -Description 'Visual Studio manifest checksum'
        MsvcManifestLength = $ManifestLength
    }
}
