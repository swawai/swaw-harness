Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'release.ps1')

function Read-SwawHarnessSelectedRelease {
    param(
        [Parameter(Mandatory = $true)][string]$EntryRoot,
        [Parameter(Mandatory = $true)][object]$Contract
    )

    $ReleasesRoot = Join-Path $EntryRoot 'releases'
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

    $SelectorPath = Join-Path $ReleasesRoot "current.$TargetId"
    $Content = "$ReleaseId`n"
    if ([IO.File]::Exists($SelectorPath) -and
        [IO.File]::ReadAllText($SelectorPath, [Text.Encoding]::UTF8) -ceq
            $Content) {
        return $SelectorPath
    }
    Write-SwawHarnessTextAtomic `
        -Path $SelectorPath `
        -Content $Content `
        -ControlledRoot (Split-Path -Path $ReleasesRoot -Parent)
    return $SelectorPath
}
