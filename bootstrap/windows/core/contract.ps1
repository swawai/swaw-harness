Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Read-SwawHarnessWindowsCoreContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    $Contract = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Windows Core build contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract `
        -Expected @(
            'schema', 'package', 'buildArtifact', 'artifact', 'staticCrt',
            'maximumBytes'
        ) `
        -Description 'Windows Core build contract'
    if ([string]$Contract.schema -cne 'swaw.harness.core-build/v2') {
        throw 'Unsupported Windows Core build contract schema.'
    }
    if ($PlatformTargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows Core v2 supports x86_64-pc-windows-msvc only.'
    }
    $Package = ([string]$Contract.package).Trim()
    if ($Package -cne 'swaw-harness-helloworld') {
        throw 'Windows Core package name is invalid.'
    }
    $BuildArtifact = ([string]$Contract.buildArtifact).Trim()
    if ($BuildArtifact -cne 'swaw-harness-helloworld.exe') {
        throw 'Windows Core build artifact name is invalid.'
    }
    $Artifact = ([string]$Contract.artifact).Trim()
    if ($Artifact -cne 'helloworld.exe') {
        throw 'Windows Core artifact name is invalid.'
    }
    if ($Contract.staticCrt -isnot [bool] -or
        -not [bool]$Contract.staticCrt) {
        throw 'Windows Core v2 requires staticCrt to be true.'
    }
    $MaximumBytes = [long]$Contract.maximumBytes
    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 64MB) {
        throw 'Windows Core maximumBytes is invalid.'
    }

    return [pscustomobject][ordered]@{
        Schema = [string]$Contract.schema
        Revision = Get-SwawHarnessFileSha256 -Path $Path
        PlatformTargetId = $PlatformTargetId
        ProductPackage = $Package
        BuildBinary = $BuildArtifact
        ProductBinary = $Artifact
        StaticCrt = [bool]$Contract.staticCrt
        MaximumBytes = $MaximumBytes
    }
}
