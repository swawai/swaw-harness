Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'release.ps1')

function Read-SwawHarnessSelectedRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ReleasesRoot,
        [Parameter(Mandatory = $true)][object]$Contract
    )

    $SelectorPath = Join-Path `
        $ReleasesRoot `
        "current.$($Contract.TargetId)"
    $Item = Get-Item `
        -LiteralPath $SelectorPath `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $Item -or $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Release selector is missing or unsafe: $SelectorPath"
    }
    if ([long]$Item.Length -ne 65) {
        throw "Release selector has invalid framing: $SelectorPath"
    }
    [byte[]]$Bytes = [IO.File]::ReadAllBytes($SelectorPath)
    if ($Bytes.Count -ne 65 -or $Bytes[64] -ne 10) {
        throw "Release selector has invalid framing: $SelectorPath"
    }
    $ReleaseId = [Text.Encoding]::ASCII.GetString($Bytes, 0, 64)
    if ($ReleaseId -cnotmatch '^[a-f0-9]{64}$') {
        throw "Release selector has an invalid identity: $SelectorPath"
    }
    return Read-SwawHarnessRelease `
        -ReleaseRoot (Join-Path $ReleasesRoot $ReleaseId) `
        -ReleaseId $ReleaseId `
        -Contract $Contract `
        -ReleasesRoot $ReleasesRoot
}

function Publish-SwawHarnessReleaseSelector {
    param(
        [Parameter(Mandatory = $true)][string]$ReleasesRoot,
        [Parameter(Mandatory = $true)][string]$TargetId,
        [Parameter(Mandatory = $true)][string]$ReleaseId
    )

    $TargetId = Get-SwawHarnessSafeSegment `
        -Value $TargetId `
        -Description 'Release selector target ID'
    if ($ReleaseId -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Release selector identity must be a lowercase SHA-256 digest.'
    }
    $SelectorPath = Join-Path $ReleasesRoot "current.$TargetId"
    $Content = "$ReleaseId`n"
    $SelectorItem = Get-Item `
        -LiteralPath $SelectorPath `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -ne $SelectorItem -and
        -not $SelectorItem.PSIsContainer -and
        ($SelectorItem.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -eq 0 -and
        [long]$SelectorItem.Length -eq 65 -and
        [IO.File]::ReadAllText($SelectorPath, [Text.Encoding]::UTF8) -ceq
            $Content) {
        return $SelectorPath
    }
    Write-SwawHarnessTextAtomic `
        -Path $SelectorPath `
        -Content $Content `
        -ControlledRoot $ReleasesRoot
    return $SelectorPath
}
