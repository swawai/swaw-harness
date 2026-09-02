Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Read-SwawHarnessWindowsCoreContracts {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    $Contract = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Windows Core build contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract `
        -Expected @('schema', 'staticCrt', 'artifacts') `
        -Description 'Windows Core build contract'
    if ([string]$Contract.schema -cne 'swaw.harness.core-build/v5') {
        throw 'Unsupported Windows Core build contract schema.'
    }
    if ($PlatformTargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows Core v5 supports x86_64-pc-windows-msvc only.'
    }
    if ($Contract.staticCrt -isnot [bool] -or
        -not [bool]$Contract.staticCrt) {
        throw 'Windows Core v5 requires staticCrt to be true.'
    }

    $Artifacts = @($Contract.artifacts)
    $Expected = @(
        [pscustomobject][ordered]@{
            Package = 'swaw-harness-helloworld'
            ModuleId = 'swaw/templates/helloworld'
            Version = '1.0.0'
            BuildArtifact = 'swaw-harness-helloworld.exe'
            Artifact = 'helloworld.exe'
        }
        [pscustomobject][ordered]@{
            Package = 'swaw-harness-dev'
            ModuleId = 'swaw/core/dev'
            Version = '1.0.2'
            BuildArtifact = 'swaw-harness-dev.exe'
            Artifact = 'swaw-harness-dev.exe'
        }
        [pscustomobject][ordered]@{
            Package = 'swaw-harness-admin'
            ModuleId = 'swaw/core/admin'
            Version = '1.0.1'
            BuildArtifact = 'swaw-harness-admin.exe'
            Artifact = 'swaw-harness-admin.exe'
        }
    )
    if ($Artifacts.Count -ne $Expected.Count) {
        throw 'Windows Core build contract must declare Helloworld, Dev, and Admin.'
    }

    $Revision = Get-SwawHarnessFileSha256 -Path $Path
    $Results = [Collections.Generic.List[object]]::new()
    for ($Index = 0; $Index -lt $Artifacts.Count; $Index++) {
        $Artifact = $Artifacts[$Index]
        $Expectation = $Expected[$Index]
        Assert-SwawHarnessObjectFields `
            -Value $Artifact `
            -Expected @(
                'package', 'module', 'version', 'buildArtifact', 'artifact',
                'maximumBytes'
            ) `
            -Description 'Windows Core build artifact contract'
        $Package = ([string]$Artifact.package).Trim()
        $ModuleId = ([string]$Artifact.module).Trim()
        $Version = ([string]$Artifact.version).Trim()
        $BuildArtifact = ([string]$Artifact.buildArtifact).Trim()
        $ProductArtifact = ([string]$Artifact.artifact).Trim()
        if ($Package -cne [string]$Expectation.Package -or
            $ModuleId -cne [string]$Expectation.ModuleId -or
            $Version -cne [string]$Expectation.Version -or
            $BuildArtifact -cne [string]$Expectation.BuildArtifact -or
            $ProductArtifact -cne [string]$Expectation.Artifact) {
            throw 'Windows Core build artifact identity is invalid.'
        }
        $MaximumBytes = [long]$Artifact.maximumBytes
        if ($MaximumBytes -le 0 -or $MaximumBytes -gt 64MB) {
            throw 'Windows Core maximumBytes is invalid.'
        }
        $Results.Add([pscustomobject][ordered]@{
            Schema = [string]$Contract.schema
            Revision = $Revision
            PlatformTargetId = $PlatformTargetId
            ProductPackage = $Package
            ModuleId = $ModuleId
            ModuleVersion = $Version
            BuildBinary = $BuildArtifact
            ProductBinary = $ProductArtifact
            StaticCrt = [bool]$Contract.staticCrt
            MaximumBytes = $MaximumBytes
        })
    }
    return $Results.ToArray()
}
