$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\msvc\manifest.ps1')

function Assert-MsvcManifestTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function New-MsvcManifestPayload {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Seed
    )

    return [pscustomobject]@{
        fileName = $FileName
        url = "https://download.visualstudio.microsoft.com/$Seed"
        size = 100 + $Seed.Length
        sha256 = Get-SwawHarnessTextSha256 -Value $Seed
    }
}

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$Config = Get-SwawHarnessMsvcRecipeConfig
$ToolVersion = '14.51'
$Packages = [Collections.Generic.List[object]]::new()
$Packages.Add([pscustomobject]@{
    id = 'microsoft.vc.14.50.18.0.tools.hostx64.targetx64.base'
    payloads = @((New-MsvcManifestPayload -FileName 'old.vsix' -Seed 'old'))
})
$Packages.Add([pscustomobject]@{
    id = 'microsoft.vc.14.52.tools.hostx64.targetx64.base'
    payloads = @((New-MsvcManifestPayload -FileName 'preview.vsix' -Seed 'preview'))
})
$Packages.Add([pscustomobject]@{
    id = 'Microsoft.VC.Preview.Tools.HostX64.TargetX64'
    version = '14.52.36615'
})
foreach ($Template in [string[]]$Config.ToolPackageTemplates) {
    $Id = $Template.Replace('{tool}', $ToolVersion)
    $Package = [ordered]@{
        id = $Id
        payloads = @((New-MsvcManifestPayload `
            -FileName "$Id.vsix" `
            -Seed $Id))
    }
    if ($Id.EndsWith('.res.base')) {
        $Package['language'] = 'en-US'
    }
    $Packages.Add([pscustomobject]$Package)
}
$SdkPayloads = [Collections.Generic.List[object]]::new()
foreach ($MsiName in [string[]]$Config.SdkMsiNames) {
    $SdkPayloads.Add((New-MsvcManifestPayload `
        -FileName "Installers/$MsiName" `
        -Seed $MsiName))
}
$SdkPayloads.Add((New-MsvcManifestPayload `
    -FileName 'Installers/sdk.cab' `
    -Seed 'sdk-cab'))
$Packages.Add([pscustomobject]@{
    id = 'Microsoft.VisualStudio.Component.Windows11SDK.28000'
    dependencies = [pscustomobject]@{
        'Win11SDK_10.0.28000' = '[10.0,11.0)'
    }
})
$Packages.Add([pscustomobject]@{
    id = 'Win11SDK_10.0.28000'
    payloads = [object[]]$SdkPayloads.ToArray()
})

$Recipe = Resolve-SwawHarnessMsvcManifest `
    -Contract $Contract `
    -VisualStudioManifest ([pscustomobject]@{
        packages = [object[]]$Packages.ToArray()
    })
Assert-MsvcManifestTest `
    -Condition (
        [string]$Contract.MsvcProductLine -ceq 'vs2026' -and
        [string]$Contract.MsvcLicenseAcceptance -ceq
            'by-bootstrap-invocation' -and
        [string]$Recipe.ToolPackageVersion -ceq $ToolVersion -and
        [string]$Recipe.SdkPackageId -ceq 'Win11SDK_10.0.28000' -and
        $Recipe.ToolPayloads.Count -eq $Config.ToolPackageTemplates.Count -and
        $Recipe.MsiPayloads.Count -eq $Config.SdkMsiNames.Count -and
        [string]$Recipe.ManifestSha256 -ceq
            [string]$Contract.MsvcManifestSha256
    ) `
    -Message 'MSVC manifest did not resolve the sealed recipe.'

$Packages.Add([pscustomobject]@{
    id = "microsoft.vc.$ToolVersion.crt.headers.base"
    payloads = @((New-MsvcManifestPayload -FileName 'duplicate.vsix' -Seed 'dup'))
})
$DuplicateRejected = $false
try {
    [void](Resolve-SwawHarnessMsvcManifest `
        -Contract $Contract `
        -VisualStudioManifest ([pscustomobject]@{
            packages = [object[]]$Packages.ToArray()
        }))
} catch {
    $DuplicateRejected = $_.Exception.Message -like '*Expected one Microsoft package*'
}
Assert-MsvcManifestTest `
    -Condition $DuplicateRejected `
    -Message 'MSVC manifest accepted an ambiguous package.'

Write-Host '[PASS] MSVC manifest test' -ForegroundColor Green
