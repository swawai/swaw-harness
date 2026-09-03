Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Read-SwawHarnessWindowsCoreHostContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    $Contract = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Windows Core Host build contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract `
        -Expected @(
            'schema', 'package', 'module', 'version', 'staticCrt',
            'buildArtifact', 'artifact', 'maximumBytes'
        ) `
        -Description 'Windows Core Host build contract'
    if ([string]$Contract.schema -cne 'swaw.harness.core-host-build/v2') {
        throw 'Unsupported Windows Core Host build contract schema.'
    }
    if ($PlatformTargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows Core Host v2 supports x86_64-pc-windows-msvc only.'
    }
    if ([string]$Contract.package -cne 'swaw-harness-core' -or
        [string]$Contract.module -cne 'swaw/core/host' -or
        [string]$Contract.version -cne '1.0.8' -or
        [string]$Contract.buildArtifact -cne 'swaw-harness-core.exe' -or
        [string]$Contract.artifact -cne 'swaw-harness-core.exe' -or
        $Contract.staticCrt -isnot [bool] -or
        -not [bool]$Contract.staticCrt) {
        throw 'Windows Core Host build identity is invalid.'
    }
    $MaximumBytes = [long]$Contract.maximumBytes
    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 64MB) {
        throw 'Windows Core Host maximumBytes is invalid.'
    }
    return [pscustomobject][ordered]@{
        Schema = [string]$Contract.schema
        Revision = Get-SwawHarnessFileSha256 -Path $Path
        PlatformTargetId = $PlatformTargetId
        ProductPackage = [string]$Contract.package
        ModuleId = [string]$Contract.module
        ModuleVersion = [string]$Contract.version
        BuildBinary = [string]$Contract.buildArtifact
        ProductBinary = [string]$Contract.artifact
        StaticCrt = [bool]$Contract.staticCrt
        MaximumBytes = $MaximumBytes
    }
}
