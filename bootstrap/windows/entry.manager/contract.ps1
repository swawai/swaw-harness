Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Read-SwawHarnessWindowsEntryManagerContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    $Contract = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Windows Entry Manager build contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract `
        -Expected @(
            'schema', 'package', 'buildArtifact', 'artifact',
            'staticCrt', 'maximumBytes'
        ) `
        -Description 'Windows Entry Manager build contract'
    if ([string]$Contract.schema -cne
        'swaw.harness.entry-manager-build/v2') {
        throw 'Unsupported Windows Entry Manager build contract schema.'
    }
    if ($PlatformTargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows Entry Manager v2 supports x86_64-pc-windows-msvc only.'
    }
    $Package = ([string]$Contract.package).Trim()
    if ($Package -cne 'swaw-har-manager') {
        throw 'Windows Entry Manager package name is invalid.'
    }
    $BuildArtifact = ([string]$Contract.buildArtifact).Trim()
    if ($BuildArtifact -cne 'swaw-har-manager.exe') {
        throw 'Windows Entry Manager build artifact name is invalid.'
    }
    $Artifact = ([string]$Contract.artifact).Trim()
    if ($Artifact -cne 'swaw-harness-entry-manager.exe') {
        throw 'Windows Entry Manager artifact name is invalid.'
    }
    if ($Contract.staticCrt -isnot [bool] -or
        -not [bool]$Contract.staticCrt) {
        throw 'Windows Entry Manager v2 requires staticCrt to be true.'
    }
    $MaximumBytes = [long]$Contract.maximumBytes
    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 64MB) {
        throw 'Windows Entry Manager maximumBytes is invalid.'
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
