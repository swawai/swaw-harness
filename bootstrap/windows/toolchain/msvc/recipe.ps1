Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\..\builder\foundation.ps1')

$script:SwawHarnessMsvcRecipeVersion = 'portable-x64-v2'

function Get-SwawHarnessMsvcRecipeConfig {
    return [pscustomobject][ordered]@{
        ResourceLanguage = 'en-US'
        ToolPackageTemplates = [string[]]@(
            'microsoft.vc.{tool}.crt.headers.base'
            'microsoft.vc.{tool}.crt.source.base'
            'microsoft.vc.{tool}.tools.hostx64.targetx64.base'
            'microsoft.vc.{tool}.tools.hostx64.targetx64.res.base'
            'microsoft.vc.{tool}.crt.x64.desktop.base'
            'microsoft.vc.{tool}.crt.x64.store.base'
            'microsoft.visualcpp.dia.sdk'
        )
        SdkMsiNames = [string[]]@(
            'Windows SDK for Windows Store Apps Tools-x86_en-us.msi'
            'Windows SDK for Windows Store Apps Headers-x86_en-us.msi'
            'Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi'
            'Windows SDK for Windows Store Apps Libs-x86_en-us.msi'
            'Universal CRT Headers Libraries and Sources-x86_en-us.msi'
            'Windows SDK Desktop Headers x64-x86_en-us.msi'
            'Windows SDK OnecoreUap Headers x64-x86_en-us.msi'
            'Windows SDK Desktop Libs x64-x86_en-us.msi'
        )
    }
}

function Get-SwawHarnessMsvcDefinitionId {
    param([Parameter(Mandatory = $true)][object]$Contract)

    $Config = Get-SwawHarnessMsvcRecipeConfig
    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        'swaw.harness.bootstrap.msvc-definition/v2'
        "recipe=$script:SwawHarnessMsvcRecipeVersion"
        "target=$($Contract.PlatformTargetId)"
        "productLine=$($Contract.MsvcProductLine)"
        "licenseUrl=$($Contract.MsvcLicenseUrl)"
        "licenseAcceptance=$($Contract.MsvcLicenseAcceptance)"
        "manifestUrl=$($Contract.MsvcManifestUrl)"
        "manifestLength=$($Contract.MsvcManifestLength)"
        "manifestSha256=$($Contract.MsvcManifestSha256)"
        "language=$($Config.ResourceLanguage)"
        "toolPackages=$([string]::Join('|', $Config.ToolPackageTemplates))"
        "sdkMsi=$([string]::Join('|', $Config.SdkMsiNames))"
    )))
}

function Get-SwawHarnessMsvcRequiredPaths {
    param(
        [Parameter(Mandatory = $true)][string]$ToolVersion,
        [Parameter(Mandatory = $true)][string]$SdkVersion
    )

    return [string[]]@(
        'setup_x64.bat'
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\cl.exe"
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\link.exe"
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\lib.exe"
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\msdia140.dll"
        "VC\Tools\MSVC\$ToolVersion\include\yvals_core.h"
        "Windows Kits\10\bin\$SdkVersion\x64\rc.exe"
        "Windows Kits\10\Include\$SdkVersion\ucrt\stdio.h"
        "Windows Kits\10\Include\$SdkVersion\um\windows.h"
        "Windows Kits\10\Lib\$SdkVersion\ucrt\x64\ucrt.lib"
        "Windows Kits\10\Lib\$SdkVersion\um\x64\kernel32.lib"
    )
}
