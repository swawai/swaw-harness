Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Read-SwawHarnessWindowsEntryManagerContracts {
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
            'schema', 'package', 'staticCrt', 'binaries'
        ) `
        -Description 'Windows Entry Manager build contract'
    if ([string]$Contract.schema -cne
        'swaw.harness.entry-manager-build/v3') {
        throw 'Unsupported Windows Entry Manager build contract schema.'
    }
    if ($PlatformTargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows Entry Manager v3 supports x86_64-pc-windows-msvc only.'
    }
    $Package = ([string]$Contract.package).Trim()
    if ($Package -cne 'swaw-har-manager') {
        throw 'Windows Entry Manager package name is invalid.'
    }
    if ($Contract.staticCrt -isnot [bool] -or
        -not [bool]$Contract.staticCrt) {
        throw 'Windows Entry Manager v3 requires staticCrt to be true.'
    }
    $Binaries = @($Contract.binaries)
    if ($Binaries.Count -ne 2) {
        throw 'Windows Entry Manager v3 requires exactly two binaries.'
    }
    $Expected = @(
        @('cli', 'swaw-harness-cli.exe', 'console'),
        @('gui', 'swaw-harness.exe', 'windows')
    )
    $Revision = Get-SwawHarnessFileSha256 -Path $Path
    for ($Index = 0; $Index -lt $Binaries.Count; $Index++) {
        $Binary = $Binaries[$Index]
        Assert-SwawHarnessObjectFields `
            -Value $Binary `
            -Expected @(
                'role', 'buildArtifact', 'artifact',
                'subsystem', 'maximumBytes'
            ) `
            -Description 'Windows Entry Manager binary contract'
        $Role = ([string]$Binary.role).Trim()
        $BuildArtifact = ([string]$Binary.buildArtifact).Trim()
        $Artifact = ([string]$Binary.artifact).Trim()
        $Subsystem = ([string]$Binary.subsystem).Trim()
        $MaximumBytes = [long]$Binary.maximumBytes
        if ($Role -cne $Expected[$Index][0] -or
            $BuildArtifact -cne $Expected[$Index][1] -or
            $Artifact -cne $Expected[$Index][1] -or
            $Subsystem -cne $Expected[$Index][2]) {
            throw 'Windows Entry Manager binary identity is invalid.'
        }
        if ($MaximumBytes -le 0 -or $MaximumBytes -gt 64MB) {
            throw 'Windows Entry Manager maximumBytes is invalid.'
        }
        Write-Output ([pscustomobject][ordered]@{
            Schema = [string]$Contract.schema
            Revision = $Revision
            PlatformTargetId = $PlatformTargetId
            ProductPackage = $Package
            Role = $Role
            BuildBinary = $BuildArtifact
            ProductBinary = $Artifact
            Subsystem = $Subsystem
            StaticCrt = [bool]$Contract.staticCrt
            MaximumBytes = $MaximumBytes
        })
    }
}
