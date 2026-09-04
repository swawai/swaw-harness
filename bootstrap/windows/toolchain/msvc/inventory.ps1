Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\inventory.ps1')
. (Join-Path $PSScriptRoot 'payload.ps1')
. (Join-Path $PSScriptRoot 'recipe.ps1')

function Get-SwawHarnessMsvcFileRecords {
    param(
        [Parameter(Mandatory = $true)][string]$MsvcRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $MsvcRoot = Get-SwawHarnessFullPath -Path $MsvcRoot
    $Prefix = $MsvcRoot.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $Records = [Collections.Generic.List[object]]::new()
    foreach ($Item in Get-SwawHarnessTreeFileItems `
        -Root $MsvcRoot `
        -ControlledRoot $ControlledRoot `
        -Description 'MSVC installation') {
        $FullPath = Get-SwawHarnessFullPath -Path $Item.FullName
        if (($Item.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "MSVC installation cannot contain a reparse point: $FullPath"
        }
        if ($Item.Length -lt 0 -or $Item.Length -gt 4GB) {
            throw "MSVC installed file is oversized: $FullPath"
        }
        if (-not $FullPath.StartsWith(
            $Prefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "MSVC inventory escaped its root: $FullPath"
        }
        $RelativePath = $FullPath.Substring($Prefix.Length)
        [void](Resolve-SwawHarnessChildPath `
            -Root $MsvcRoot `
            -RelativePath $RelativePath `
            -Description 'MSVC inventory file')
        $Records.Add([pscustomobject][ordered]@{
            path = $RelativePath
            kind = 'file'
            target = ''
            length = [long]$Item.Length
            sha256 = Get-SwawHarnessFileSha256 -Path $FullPath
        })
    }
    return Sort-SwawHarnessPathRecords -Records $Records.ToArray()
}

function Get-SwawHarnessMsvcFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$MsvcRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $MsvcRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $MsvcRoot `
        -Root $ControlledRoot `
        -Activity 'validating an MSVC installation'
    [void](Assert-SwawHarnessControlledRoot `
        -Root $MsvcRoot `
        -Description 'MSVC installation root')
    $Path = Resolve-SwawHarnessChildPath `
        -Root $MsvcRoot `
        -RelativePath $RelativePath `
        -Description 'MSVC critical file'
    $Path = Assert-SwawHarnessPathInsideRoot `
        -Path $Path `
        -Root $ControlledRoot `
        -Activity 'validating an MSVC critical file'
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $Item.Length -le 0 -or $Item.Length -gt 4GB) {
        throw "MSVC critical file is invalid: $RelativePath"
    }
    $Prefix = $MsvcRoot.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $FullPath = Get-SwawHarnessFullPath -Path $Item.FullName
    if (-not $FullPath.StartsWith(
        $Prefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "MSVC critical file escaped its root: $FullPath"
    }
    return [pscustomobject][ordered]@{
        path = $FullPath.Substring($Prefix.Length)
        kind = 'file'
        target = ''
        length = [long]$Item.Length
        sha256 = Get-SwawHarnessFileSha256 -Path $FullPath
    }
}

function ConvertTo-SwawHarnessMsvcPayloadRecord {
    param([Parameter(Mandatory = $true)][object]$Payload)

    return [pscustomobject][ordered]@{
        fileName = [string]$Payload.FileName
        leafName = [string]$Payload.LeafName
        url = [string]$Payload.Url
        declaredSize = [long]$Payload.DeclaredSize
        length = [long]$Payload.Length
        sha256 = [string]$Payload.Sha256
    }
}

function New-SwawHarnessMsvcInstallRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][object]$Versions,
        [Parameter(Mandatory = $true)][object[]]$UsedPayloads,
        [Parameter(Mandatory = $true)][string]$MsvcRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $SeenPayloads = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $PayloadRecords = [Collections.Generic.List[object]]::new()
    foreach ($Payload in $UsedPayloads) {
        $Key = [string]::Join("`n", @(
            [string]$Payload.FileName,
            [string]$Payload.Url,
            [string]$Payload.Sha256
        ))
        if ($SeenPayloads.Add($Key)) {
            $PayloadRecords.Add(
                (ConvertTo-SwawHarnessMsvcPayloadRecord -Payload $Payload)
            )
        }
    }
    if ($PayloadRecords.Count -eq 0) {
        throw 'MSVC installation must record its verified source payloads.'
    }
    $SortedPayloads = [object[]]$PayloadRecords.ToArray()
    if ($SortedPayloads.Count -gt 1) {
        $PayloadComparison = [Comparison[object]]{
            param($Left, $Right)

            foreach ($Name in @('fileName', 'url', 'sha256')) {
                $Result = [StringComparer]::Ordinal.Compare(
                    [string]$Left.$Name,
                    [string]$Right.$Name
                )
                if ($Result -ne 0) {
                    return $Result
                }
            }
            return 0
        }
        [Array]::Sort($SortedPayloads, $PayloadComparison)
    }
    $Files = @(Get-SwawHarnessMsvcFileRecords `
        -MsvcRoot $MsvcRoot `
        -ControlledRoot $ControlledRoot)
    if ($Files.Count -eq 0) {
        throw 'MSVC installation inventory cannot be empty.'
    }
    $RequiredPaths = Get-SwawHarnessMsvcRequiredPaths `
        -ToolVersion ([string]$Versions.ToolVersion) `
        -SdkVersion ([string]$Versions.SdkVersion)
    $CriticalFiles = @(Select-SwawHarnessRequiredFileRecords `
        -Records $Files `
        -RequiredPaths $RequiredPaths `
        -Description 'MSVC installation')
    return [pscustomobject][ordered]@{
        schema = 'swaw.harness.bootstrap.msvc-install/v3'
        definitionId = Get-SwawHarnessMsvcDefinitionId -Contract $Contract
        productLine = [string]$Contract.MsvcProductLine
        license = [pscustomobject][ordered]@{
            url = [string]$Contract.MsvcLicenseUrl
            acceptance = [string]$Contract.MsvcLicenseAcceptance
        }
        manifest = [pscustomobject][ordered]@{
            url = [string]$Recipe.ManifestUrl
            length = [long]$Recipe.ManifestLength
            sha256 = [string]$Recipe.ManifestSha256
        }
        toolPackageVersion = [string]$Recipe.ToolPackageVersion
        toolVersion = [string]$Versions.ToolVersion
        sdkPackageId = [string]$Recipe.SdkPackageId
        sdkVersion = [string]$Versions.SdkVersion
        payloads = $SortedPayloads
        inventory = Get-SwawHarnessFileInventorySummary `
            -Records $Files `
            -Description 'MSVC installation'
        criticalFiles = $CriticalFiles
    }
}

function Test-SwawHarnessMsvcInstallRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$MsvcRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [switch]$Full,
        [switch]$Detailed
    )

    try {
        Assert-SwawHarnessObjectFields `
            -Value $Record `
            -Expected @(
                'schema', 'definitionId', 'productLine', 'license', 'manifest',
                'toolPackageVersion', 'toolVersion', 'sdkPackageId',
                'sdkVersion', 'payloads', 'inventory', 'criticalFiles'
            ) `
            -Description 'MSVC install record'
        Assert-SwawHarnessObjectFields `
            -Value $Record.license `
            -Expected @('url', 'acceptance') `
            -Description 'MSVC license record'
        Assert-SwawHarnessObjectFields `
            -Value $Record.manifest `
            -Expected @('url', 'length', 'sha256') `
            -Description 'MSVC manifest record'
        if ([string]$Record.schema -cne
                'swaw.harness.bootstrap.msvc-install/v3' -or
            [string]$Record.definitionId -cne
                (Get-SwawHarnessMsvcDefinitionId -Contract $Contract) -or
            [string]$Record.productLine -cne
                [string]$Contract.MsvcProductLine -or
            [string]$Record.license.url -cne
                [string]$Contract.MsvcLicenseUrl -or
            [string]$Record.license.acceptance -cne
                [string]$Contract.MsvcLicenseAcceptance -or
            [string]$Record.manifest.url -cne
                [string]$Contract.MsvcManifestUrl -or
            [long]$Record.manifest.length -ne
                [long]$Contract.MsvcManifestLength -or
            [string]$Record.manifest.sha256 -cne
                [string]$Contract.MsvcManifestSha256 -or
            [string]$Record.toolPackageVersion -cnotmatch
                '^\d+\.\d+(?:\.\d+\.\d+)?$' -or
            [string]$Record.toolVersion -cnotmatch '^\d+(\.\d+)+$' -or
            [string]$Record.sdkPackageId -cnotmatch '^Win1[01]SDK_' -or
            [string]$Record.sdkVersion -cnotmatch '^\d+(\.\d+)+$') {
            throw 'MSVC install identity record is inconsistent.'
        }

        $RecordedPayloads = @($Record.payloads)
        if ($RecordedPayloads.Count -eq 0 -or
            $RecordedPayloads.Count -gt 10000) {
            throw 'MSVC source payload record count is invalid.'
        }
        $PayloadKeys = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::Ordinal
        )
        foreach ($Payload in $RecordedPayloads) {
            Assert-SwawHarnessObjectFields `
                -Value $Payload `
                -Expected @(
                    'fileName', 'leafName', 'url', 'declaredSize',
                    'length', 'sha256'
                ) `
                -Description 'MSVC source payload record'
            $Converted = ConvertTo-SwawHarnessMsvcPayload `
                -Payload ([pscustomobject]@{
                    fileName = [string]$Payload.fileName
                    url = [string]$Payload.url
                    size = [long]$Payload.declaredSize
                    sha256 = [string]$Payload.sha256
                }) `
                -Description 'recorded MSVC source'
            if ([string]$Payload.leafName -cne
                    [string]$Converted.LeafName -or
                [long]$Payload.length -le 0 -or
                [long]$Payload.length -gt 4GB) {
                throw 'MSVC source payload shape is invalid.'
            }
            $PayloadKey = [string]::Join("`n", @(
                [string]$Payload.fileName,
                [string]$Payload.url,
                [string]$Payload.sha256
            ))
            if (-not $PayloadKeys.Add($PayloadKey)) {
                throw 'MSVC source payload record is duplicated.'
            }
        }

        Assert-SwawHarnessFileInventorySummary `
            -Summary $Record.inventory `
            -Description 'MSVC inventory summary'
        $RequiredPaths = Get-SwawHarnessMsvcRequiredPaths `
            -ToolVersion ([string]$Record.toolVersion) `
            -SdkVersion ([string]$Record.sdkVersion)
        $RecordedCriticalFiles = @($Record.criticalFiles)
        if ($RecordedCriticalFiles.Count -ne $RequiredPaths.Count) {
            throw 'MSVC critical file record count is invalid.'
        }
        $SelectedCriticalFiles = @(Select-SwawHarnessRequiredFileRecords `
            -Records $RecordedCriticalFiles `
            -RequiredPaths $RequiredPaths `
            -Description 'MSVC critical files')
        for ($Index = 0; $Index -lt $RequiredPaths.Count; $Index++) {
            $Actual = Get-SwawHarnessMsvcFileRecord `
                -MsvcRoot $MsvcRoot `
                -ControlledRoot $ControlledRoot `
                -RelativePath $RequiredPaths[$Index]
            if (-not (Test-SwawHarnessFileInventoryRecordEqual `
                -Left $SelectedCriticalFiles[$Index] `
                -Right $Actual)) {
                throw "MSVC critical file differs: $($RequiredPaths[$Index])"
            }
        }
        if ($Full) {
            $ActualSummary = Get-SwawHarnessFileInventorySummary `
                -Records @(Get-SwawHarnessMsvcFileRecords `
                    -MsvcRoot $MsvcRoot `
                    -ControlledRoot $ControlledRoot) `
                -Description 'MSVC installation'
            if ([long]$ActualSummary.fileCount -ne
                    [long]$Record.inventory.fileCount -or
                [long]$ActualSummary.totalLength -ne
                    [long]$Record.inventory.totalLength -or
                [string]$ActualSummary.sha256 -cne
                    [string]$Record.inventory.sha256) {
                throw 'MSVC full inventory summary changed.'
            }
        }
        return $true
    } catch {
        if ($Detailed) {
            throw
        }
        return $false
    }
}
