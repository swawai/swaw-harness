Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\foundation.ps1')

$script:SwawHarnessReleaseSchema = 'swaw.harness.release/v1'

function Get-SwawHarnessReleaseId {
    param(
        [Parameter(Mandatory = $true)][string]$TargetId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][long]$Length,
        [Parameter(Mandatory = $true)][string]$Sha256
    )

    $LengthText = $Length.ToString(
        [Globalization.CultureInfo]::InvariantCulture
    )
    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        $script:SwawHarnessReleaseSchema,
        "target=$TargetId",
        "artifact=$Name",
        "length=$LengthText",
        "sha256=$Sha256"
    )))
}

function Read-SwawHarnessRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseRoot,
        [Parameter(Mandatory = $true)][string]$ReleaseId,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$ReleasesRoot
    )

    if ($ReleaseId -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Release ID must be a lowercase SHA-256 digest.'
    }
    $ReleaseRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $ReleaseRoot `
        -Root $ReleasesRoot `
        -Activity 'reading a Release'
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

    [string[]]$ExpectedNames = @('manifest.json', $Contract.ProductBinary)
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
        -Description 'Release manifest'
    Assert-SwawHarnessObjectFields `
        -Value $Manifest `
        -Expected @('schema', 'releaseId', 'targetId', 'artifacts') `
        -Description 'Release manifest'
    $Artifacts = @($Manifest.artifacts)
    if ($Artifacts.Count -ne 1) {
        throw "Release manifest must declare exactly one artifact: $ManifestPath"
    }
    Assert-SwawHarnessObjectFields `
        -Value $Artifacts[0] `
        -Expected @('name', 'length', 'sha256') `
        -Description 'Release artifact record'
    $Record = $Artifacts[0]
    $ArtifactPath = Join-Path $ReleaseRoot ([string]$Record.name)
    $Item = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Release artifact'
    $Sha256 = ([string]$Record.sha256).Trim().ToLowerInvariant()
    if ([string]$Manifest.schema -cne $script:SwawHarnessReleaseSchema -or
        [string]$Manifest.releaseId -cne $ReleaseId -or
        [string]$Manifest.targetId -cne [string]$Contract.TargetId -or
        [string]$Record.name -cne [string]$Contract.ProductBinary -or
        [long]$Record.length -ne [long]$Item.Length -or
        $Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-SwawHarnessFileSha256 -Path $ArtifactPath) -cne $Sha256) {
        throw "Release validation failed: $ReleaseRoot"
    }
    $ComputedId = Get-SwawHarnessReleaseId `
        -TargetId ([string]$Manifest.targetId) `
        -Name ([string]$Record.name) `
        -Length ([long]$Record.length) `
        -Sha256 $Sha256
    if ($ComputedId -cne $ReleaseId) {
        throw "Release identity does not match its content: $ReleaseRoot"
    }

    return [pscustomobject][ordered]@{
        ReleaseId = $ReleaseId
        TargetId = [string]$Manifest.targetId
        Root = $ReleaseRoot
        ManifestPath = $ManifestPath
        ArtifactPath = $ArtifactPath
    }
}
