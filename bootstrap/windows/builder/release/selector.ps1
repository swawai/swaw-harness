Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'release.ps1')

function Read-SwawHarnessReleaseSelectorBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Path = Get-SwawHarnessFullPath -Path $Path
    $Item = Get-Item `
        -LiteralPath $Path `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $Item -or $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Release selector is missing or unsafe: $Path"
    }
    $Stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    try {
        if ($Stream.Length -ne 65) {
            throw "Release selector has invalid framing: $Path"
        }
        [byte[]]$Bytes = [byte[]]::new(65)
        $Offset = 0
        while ($Offset -lt $Bytes.Length) {
            $Read = $Stream.Read($Bytes, $Offset, $Bytes.Length - $Offset)
            if ($Read -le 0) {
                break
            }
            $Offset += $Read
        }
        if ($Offset -ne $Bytes.Length -or $Stream.ReadByte() -ne -1) {
            throw "Release selector has invalid framing: $Path"
        }
        return ,$Bytes
    } finally {
        $Stream.Dispose()
    }
}

function Read-SwawHarnessSelectedRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ReleasesRoot,
        [Parameter(Mandatory = $true)][object[]]$Contracts
    )

    $TargetId = Get-SwawHarnessReleaseTargetId -Contracts $Contracts
    $SelectorPath = Join-Path `
        $ReleasesRoot `
        "current.$TargetId"
    [byte[]]$Bytes = Read-SwawHarnessReleaseSelectorBytes `
        -Path $SelectorPath
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
        -Contracts $Contracts `
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
    $MatchesCurrent = $false
    try {
        [byte[]]$ExistingBytes = Read-SwawHarnessReleaseSelectorBytes `
            -Path $SelectorPath
        $MatchesCurrent = [Text.Encoding]::ASCII.GetString($ExistingBytes) -ceq
            $Content
    } catch {}
    if ($MatchesCurrent) {
        return $SelectorPath
    }
    Write-SwawHarnessTextAtomic `
        -Path $SelectorPath `
        -Content $Content `
        -ControlledRoot $ReleasesRoot
    return $SelectorPath
}
