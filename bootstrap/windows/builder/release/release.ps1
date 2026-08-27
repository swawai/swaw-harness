Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\foundation.ps1')

$script:SwawHarnessReleaseSchema = 'swaw.harness.bootstrap-release/v1'

function Get-SwawHarnessReleasePlatformTargetId {
    param([Parameter(Mandatory = $true)][object[]]$Contracts)

    if ($Contracts.Count -eq 0 -or $Contracts.Count -gt 32) {
        throw 'Bootstrap Release must contain between 1 and 32 products.'
    }
    $PlatformTargetId = [string]$Contracts[0].PlatformTargetId
    [void](Get-SwawHarnessSafeSegment `
        -Value $PlatformTargetId `
        -Description 'Bootstrap Release platform target ID')
    $Names = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    foreach ($Contract in $Contracts) {
        $Name = [string]$Contract.ProductBinary
        [void](Get-SwawHarnessSafeSegment `
            -Value $Name `
            -Description 'Bootstrap Release artifact name')
        if ([string]$Contract.PlatformTargetId -cne $PlatformTargetId -or
            [long]$Contract.MaximumBytes -le 0 -or
            -not $Names.Add($Name)) {
            throw 'Bootstrap Release product contracts are inconsistent.'
        }
    }
    return $PlatformTargetId
}

function Get-SwawHarnessReleaseId {
    param(
        [Parameter(Mandatory = $true)][string]$PlatformTargetId,
        [Parameter(Mandatory = $true)][object[]]$Artifacts
    )

    $Lines = [Collections.Generic.List[string]]::new()
    $Lines.Add($script:SwawHarnessReleaseSchema)
    $Lines.Add("target=$PlatformTargetId")
    foreach ($Artifact in $Artifacts) {
        $Length = [long]$Artifact.Length
        $Sha256 = ([string]$Artifact.Sha256).Trim().ToLowerInvariant()
        if ($Length -le 0 -or $Sha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Bootstrap Release artifact identity is invalid.'
        }
        $Lines.Add("artifact=$([string]$Artifact.Name)")
        $Lines.Add("length=$($Length.ToString(
            [Globalization.CultureInfo]::InvariantCulture
        ))")
        $Lines.Add("sha256=$Sha256")
    }
    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", $Lines))
}

function Read-SwawHarnessRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseRoot,
        [Parameter(Mandatory = $true)][string]$ReleaseId,
        [Parameter(Mandatory = $true)][object[]]$Contracts,
        [Parameter(Mandatory = $true)][string]$ReleasesRoot
    )

    $PlatformTargetId = Get-SwawHarnessReleasePlatformTargetId `
        -Contracts $Contracts
    if ($ReleaseId -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Release ID must be a lowercase SHA-256 digest.'
    }
    $ReleaseRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $ReleaseRoot `
        -Root $ReleasesRoot `
        -Activity 'reading a Bootstrap Release'
    if ([IO.Path]::GetFileName($ReleaseRoot) -cne $ReleaseId) {
        throw "Release directory does not match its identity: $ReleaseRoot"
    }
    $RootItem = Get-Item `
        -LiteralPath $ReleaseRoot `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $RootItem -or -not $RootItem.PSIsContainer -or
        ($RootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Release directory is missing or unsafe: $ReleaseRoot"
    }

    [string[]]$ExpectedNames = @('manifest.json') + @(
        $Contracts | ForEach-Object { [string]$_.ProductBinary }
    )
    [string[]]$ActualNames = @(
        Get-ChildItem -LiteralPath $ReleaseRoot -Force |
            ForEach-Object { [string]$_.Name }
    )
    if ($ActualNames.Count -ne $ExpectedNames.Count) {
        throw "Release membership is invalid: $ReleaseRoot"
    }
    foreach ($Name in $ExpectedNames) {
        if ($ActualNames -cnotcontains $Name) {
            throw "Release membership is invalid: $ReleaseRoot"
        }
    }

    $ManifestPath = Join-Path $ReleaseRoot 'manifest.json'
    $Manifest = Read-SwawHarnessJsonFile `
        -Path $ManifestPath `
        -Description 'Bootstrap Release manifest'
    Assert-SwawHarnessObjectFields `
        -Value $Manifest `
        -Expected @('schema', 'releaseId', 'platformTargetId', 'artifacts') `
        -Description 'Bootstrap Release manifest'
    $Records = @($Manifest.artifacts)
    if ($Records.Count -ne $Contracts.Count) {
        throw "Release manifest has an invalid product count: $ManifestPath"
    }

    $Artifacts = [Collections.Generic.List[object]]::new()
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $Contract = $Contracts[$Index]
        $Record = $Records[$Index]
        Assert-SwawHarnessObjectFields `
            -Value $Record `
            -Expected @('name', 'length', 'sha256') `
            -Description 'Bootstrap Release artifact record'
        $Name = [string]$Record.name
        if ($Name -cne [string]$Contract.ProductBinary) {
            throw "Release artifact order or name is invalid: $ManifestPath"
        }
        $Path = Resolve-SwawHarnessChildPath `
            -Root $ReleaseRoot `
            -RelativePath $Name `
            -Description 'Bootstrap Release artifact'
        $Item = Assert-SwawHarnessRegularFile `
            -Path $Path `
            -Description 'Bootstrap Release artifact' `
            -MaximumBytes ([long]$Contract.MaximumBytes)
        $Sha256 = ([string]$Record.sha256).Trim().ToLowerInvariant()
        if ([long]$Record.length -ne [long]$Item.Length -or
            $Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            (Get-SwawHarnessFileSha256 -Path $Path) -cne $Sha256) {
            throw "Release artifact validation failed: $Path"
        }
        $Artifacts.Add([pscustomobject][ordered]@{
            Name = $Name
            Length = [long]$Item.Length
            Sha256 = $Sha256
            Path = $Path
        })
    }
    if ([string]$Manifest.schema -cne $script:SwawHarnessReleaseSchema -or
        [string]$Manifest.releaseId -cne $ReleaseId -or
        [string]$Manifest.platformTargetId -cne $PlatformTargetId) {
        throw "Release validation failed: $ReleaseRoot"
    }
    $ComputedId = Get-SwawHarnessReleaseId `
        -PlatformTargetId $PlatformTargetId `
        -Artifacts $Artifacts.ToArray()
    if ($ComputedId -cne $ReleaseId) {
        throw "Release identity does not match its content: $ReleaseRoot"
    }

    return [pscustomobject][ordered]@{
        ReleaseId = $ReleaseId
        PlatformTargetId = $PlatformTargetId
        Root = $ReleaseRoot
        ManifestPath = $ManifestPath
        Artifacts = $Artifacts.ToArray()
    }
}
