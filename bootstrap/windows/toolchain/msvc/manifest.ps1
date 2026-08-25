Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\download-cache.ps1')
. (Join-Path $PSScriptRoot 'payload.ps1')
. (Join-Path $PSScriptRoot 'recipe.ps1')

function Get-SwawHarnessMsvcPackage {
    param(
        [Parameter(Mandatory = $true)][object[]]$Packages,
        [Parameter(Mandatory = $true)][string]$Id,
        [AllowNull()][string]$Language = $null
    )

    $Matches = @($Packages | Where-Object {
        [string]$_.id -ieq $Id
    })
    if ([string]::IsNullOrWhiteSpace($Language)) {
        $Matches = @($Matches | Where-Object {
            $Property = $_.PSObject.Properties['language']
            $null -eq $Property -or
                [string]::IsNullOrWhiteSpace([string]$Property.Value)
        })
    } else {
        $Matches = @($Matches | Where-Object {
            $Property = $_.PSObject.Properties['language']
            $null -ne $Property -and
                [string]$Property.Value -ieq $Language
        })
    }
    if ($Matches.Count -ne 1) {
        $Suffix = if ([string]::IsNullOrWhiteSpace($Language)) {
            ''
        } else {
            " for language '$Language'"
        }
        throw (
            "Expected one Microsoft package '$Id'$Suffix; found " +
            "$($Matches.Count)."
        )
    }
    return $Matches[0]
}

function Get-SwawHarnessMsvcPackagePayloads {
    param(
        [Parameter(Mandatory = $true)][object]$Package,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $PayloadProperty = $Package.PSObject.Properties['payloads']
    $Payloads = @(if ($null -eq $PayloadProperty) {
        @()
    } else {
        @($PayloadProperty.Value)
    })
    if ($Payloads.Count -eq 0) {
        throw "Microsoft package has no payloads: $Description"
    }
    return [object[]]@($Payloads | ForEach-Object {
        ConvertTo-SwawHarnessMsvcPayload `
            -Payload $_ `
            -Description $Description
    })
}

function Resolve-SwawHarnessMsvcManifest {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$VisualStudioManifest
    )

    $PackagesProperty = $VisualStudioManifest.PSObject.Properties['packages']
    $Packages = @(if ($null -eq $PackagesProperty) {
        @()
    } else {
        @($PackagesProperty.Value)
    })
    if ($Packages.Count -eq 0 -or $Packages.Count -gt 200000) {
        throw 'The Visual Studio manifest has an invalid package count.'
    }
    $Config = Get-SwawHarnessMsvcRecipeConfig

    $PreviewPackages = @($Packages | Where-Object {
        [string]$_.id -ieq 'Microsoft.VC.Preview.Tools.HostX64.TargetX64'
    })
    if ($PreviewPackages.Count -gt 1) {
        throw 'The VS manifest has multiple MSVC preview markers.'
    }
    $PreviewFamily = $null
    if ($PreviewPackages.Count -eq 1) {
        $VersionProperty = $PreviewPackages[0].PSObject.Properties['version']
        $PreviewMatch = if ($null -eq $VersionProperty) {
            $null
        } else {
            [regex]::Match([string]$VersionProperty.Value, '^(\d+\.\d+)')
        }
        if ($null -eq $PreviewMatch -or -not $PreviewMatch.Success) {
            throw 'The VS manifest has an invalid MSVC preview marker.'
        }
        $PreviewFamily = [string]$PreviewMatch.Groups[1].Value
    }
    $ToolCandidates = foreach ($Package in $Packages) {
        $IdProperty = $Package.PSObject.Properties['id']
        if ($null -eq $IdProperty) {
            continue
        }
        $Match = [regex]::Match(
            ([string]$IdProperty.Value).ToLowerInvariant(),
            '^microsoft\.vc\.(\d+\.\d+(?:\.\d+\.\d+)?)\.' +
                'tools\.hostx64\.targetx64\.base$'
        )
        if ($Match.Success) {
            $Text = [string]$Match.Groups[1].Value
            $Parts = $Text.Split('.')
            $Family = "$($Parts[0]).$($Parts[1])"
            if ($null -ne $PreviewFamily -and $Family -ceq $PreviewFamily) {
                continue
            }
            [pscustomobject][ordered]@{
                Version = [version]$Text
                Text = $Text
            }
        }
    }
    $Tool = @($ToolCandidates | Sort-Object Version -Descending |
        Select-Object -First 1)
    if ($Tool.Count -ne 1) {
        throw 'No x64 MSVC tool package was found in the VS manifest.'
    }

    $ToolPayloads = [Collections.Generic.List[object]]::new()
    foreach ($Template in [string[]]$Config.ToolPackageTemplates) {
        $Id = $Template.Replace('{tool}', [string]$Tool[0].Text)
        $Language = if ($Id.EndsWith(
            '.res.base',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            [string]$Config.ResourceLanguage
        } else {
            $null
        }
        $Package = Get-SwawHarnessMsvcPackage `
            -Packages $Packages `
            -Id $Id `
            -Language $Language
        foreach ($Payload in Get-SwawHarnessMsvcPackagePayloads `
            -Package $Package `
            -Description $Id) {
            $ToolPayloads.Add($Payload)
        }
    }

    $SdkCandidates = foreach ($Package in $Packages) {
        $IdProperty = $Package.PSObject.Properties['id']
        if ($null -eq $IdProperty) {
            continue
        }
        $Match = [regex]::Match(
            ([string]$IdProperty.Value).ToLowerInvariant(),
            '^microsoft\.visualstudio\.component\.windows1[01]sdk\.(\d+)$'
        )
        if ($Match.Success) {
            [pscustomobject][ordered]@{
                Number = [long]$Match.Groups[1].Value
                Package = $Package
            }
        }
    }
    $SdkComponent = @($SdkCandidates | Sort-Object Number -Descending |
        Select-Object -First 1)
    if ($SdkComponent.Count -ne 1) {
        throw 'No Windows 10/11 SDK component was found in the VS manifest.'
    }
    $DependenciesProperty =
        $SdkComponent[0].Package.PSObject.Properties['dependencies']
    $Dependencies = @(if ($null -eq $DependenciesProperty -or
        $null -eq $DependenciesProperty.Value) {
        @()
    } else {
        @($DependenciesProperty.Value.PSObject.Properties.Name |
            Where-Object { $_ -match '^Win1[01]SDK_' })
    })
    if ($Dependencies.Count -ne 1) {
        throw (
            "SDK component '$($SdkComponent[0].Package.id)' must identify " +
            'exactly one Windows SDK package.'
        )
    }
    $SdkPackage = Get-SwawHarnessMsvcPackage `
        -Packages $Packages `
        -Id ([string]$Dependencies[0])
    $SdkPayloads = Get-SwawHarnessMsvcPackagePayloads `
        -Package $SdkPackage `
        -Description ([string]$SdkPackage.id)
    $MsiPayloads = [Collections.Generic.List[object]]::new()
    foreach ($MsiName in [string[]]$Config.SdkMsiNames) {
        $Expected = "Installers/$MsiName"
        $Matches = @($SdkPayloads | Where-Object {
            ([string]$_.FileName).Replace('\', '/') -ieq $Expected
        })
        if ($Matches.Count -ne 1) {
            throw (
                "Expected one Windows SDK payload '$Expected'; found " +
                "$($Matches.Count)."
            )
        }
        $MsiPayloads.Add($Matches[0])
    }

    return [pscustomobject][ordered]@{
        ManifestUrl = [string]$Contract.MsvcManifestUrl
        ManifestLength = [long]$Contract.MsvcManifestLength
        ManifestSha256 = [string]$Contract.MsvcManifestSha256
        ToolPackageVersion = [string]$Tool[0].Text
        ToolPayloads = [object[]]$ToolPayloads.ToArray()
        SdkPackageId = [string]$SdkPackage.id
        SdkPayloads = [object[]]$SdkPayloads
        MsiPayloads = [object[]]$MsiPayloads.ToArray()
    }
}

function Get-SwawHarnessMsvcInstallRecipe {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract
    )

    $ManifestPath = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source ([string]$Contract.MsvcManifestUrl) `
        -ExpectedLength ([long]$Contract.MsvcManifestLength) `
        -ExpectedSha256 ([string]$Contract.MsvcManifestSha256) `
        -Description 'Visual Studio package manifest'
    $Manifest = Read-SwawHarnessJsonFile `
        -Path $ManifestPath `
        -Description 'Visual Studio package manifest' `
        -MaximumBytes 64MB
    return Resolve-SwawHarnessMsvcManifest `
        -Contract $Contract `
        -VisualStudioManifest $Manifest
}
