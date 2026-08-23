[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$VarRoot,
    [Parameter(Mandatory = $true)][string]$EntryRoot,
    [Parameter(Mandatory = $true)][string]$CandidatePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '_lib\contract.ps1')
. (Join-Path $PSScriptRoot '_lib\build\candidate.ps1')
. (Join-Path $PSScriptRoot '_lib\release\release.ps1')
. (Join-Path $PSScriptRoot '_lib\release\selector.ps1')
. (Join-Path $PSScriptRoot '_lib\filesystem.ps1')

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot 'contract.json')
$VarRoot = Assert-SwawHarnessControlledRoot `
    -Root $VarRoot `
    -Description 'VarRoot'
$CacheRoot = Assert-SwawHarnessPathInsideRoot `
    -Path (Join-Path $VarRoot 'var_cache') `
    -Root $VarRoot `
    -Activity 'using var_cache'
[void][IO.Directory]::CreateDirectory($CacheRoot)
$BuildRoot = Join-Path $CacheRoot (
    "bootstrap\windows\build\$($Contract.TargetId)"
)
$Candidate = Read-SwawHarnessBootstrapCandidate `
    -Path $CandidatePath `
    -Contract $Contract `
    -BuildRoot $BuildRoot
$ReleaseId = Get-SwawHarnessReleaseId `
    -TargetId ([string]$Candidate.TargetId) `
    -Name ([string]$Candidate.Name) `
    -Length ([long]$Candidate.Length) `
    -Sha256 ([string]$Candidate.Sha256)

$EntrySpace = Assert-SwawHarnessPathInsideRoot `
    -Path (Join-Path $VarRoot 'var_entry') `
    -Root $VarRoot `
    -Activity 'using var_entry'
$EntryRoot = Get-SwawHarnessFullPath -Path $EntryRoot
if (-not (Split-Path -Path $EntryRoot -Parent).Equals(
    $EntrySpace,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "EntryRoot must be a direct child of var_entry: $EntryRoot"
}
[void](Assert-SwawHarnessPathInsideRoot `
    -Path $EntryRoot `
    -Root $EntrySpace `
    -Activity 'publishing an Entry Release')
[void][IO.Directory]::CreateDirectory($EntryRoot)
$ReleasesRoot = Join-Path $EntryRoot 'releases'
[void](Assert-SwawHarnessPathInsideRoot `
    -Path $ReleasesRoot `
    -Root $EntryRoot `
    -Activity 'publishing a Release')
[void][IO.Directory]::CreateDirectory($ReleasesRoot)

$LockKey = Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
    $EntryRoot.ToLowerInvariant(),
    [string]$Contract.TargetId
)))
$LockRoot = Join-Path $CacheRoot 'bootstrap\windows\locks'
$Lock = Enter-SwawHarnessFileLock `
    -Path (Join-Path $LockRoot "publish-$LockKey.lock") `
    -ControlledRoot $CacheRoot
try {
    foreach ($WorkItem in Get-ChildItem -LiteralPath $ReleasesRoot -Force) {
        if ([string]$WorkItem.Name -cmatch
            '^\.publish-[a-f0-9]{32}\.tmp$') {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path ([string]$WorkItem.FullName) `
                -ControlledRoot $EntryRoot `
                -Activity 'cleaning interrupted Release publication'
        }
    }
    $ReleaseRoot = Join-Path $ReleasesRoot $ReleaseId
    $ExistingRelease = $null
    if (Test-SwawHarnessPathExists -Path $ReleaseRoot) {
        try {
            $ExistingRelease = Read-SwawHarnessRelease `
                -ReleaseRoot $ReleaseRoot `
                -ReleaseId $ReleaseId `
                -Contract $Contract `
                -ReleasesRoot $ReleasesRoot
        } catch {
            $ExistingRelease = $null
        }
    }
    if ($null -eq $ExistingRelease) {
        $StageParent = Join-Path $ReleasesRoot (
            ".publish-$([Guid]::NewGuid().ToString('N')).tmp"
        )
        $StageRoot = Join-Path $StageParent $ReleaseId
        [void][IO.Directory]::CreateDirectory($StageRoot)
        try {
            $Destination = Join-Path $StageRoot $Candidate.Name
            [IO.File]::Copy($Candidate.ArtifactPath, $Destination, $false)
            $Item = Assert-SwawHarnessRegularFile `
                -Path $Destination `
                -Description 'Staged Release artifact'
            $Hash = Get-SwawHarnessFileSha256 -Path $Destination
            if ([long]$Item.Length -ne [long]$Candidate.Length -or
                $Hash -cne [string]$Candidate.Sha256) {
                throw "Staged Release artifact is corrupt: $Destination"
            }
            $Manifest = [ordered]@{
                schema = $script:SwawHarnessReleaseSchema
                releaseId = [string]$ReleaseId
                targetId = [string]$Contract.TargetId
                artifacts = @([ordered]@{
                    name = [string]$Candidate.Name
                    length = [long]$Candidate.Length
                    sha256 = [string]$Candidate.Sha256
                })
            }
            [IO.File]::WriteAllText(
                (Join-Path $StageRoot 'manifest.json'),
                (ConvertTo-SwawHarnessJsonText -Value $Manifest),
                [Text.UTF8Encoding]::new($false)
            )
            [void](Read-SwawHarnessRelease `
                -ReleaseRoot $StageRoot `
                -ReleaseId $ReleaseId `
                -Contract $Contract `
                -ReleasesRoot $ReleasesRoot)
            if (Test-SwawHarnessPathExists -Path $ReleaseRoot) {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path $ReleaseRoot `
                    -ControlledRoot $EntryRoot `
                    -Activity 'removing a corrupt content-addressed Release'
            }
            [IO.Directory]::Move($StageRoot, $ReleaseRoot)
        } finally {
            if ([IO.Directory]::Exists($StageParent)) {
                [IO.Directory]::Delete($StageParent, $true)
            }
        }
    }

    $Release = Read-SwawHarnessRelease `
        -ReleaseRoot $ReleaseRoot `
        -ReleaseId $ReleaseId `
        -Contract $Contract `
        -ReleasesRoot $ReleasesRoot
    $SelectorPath = Join-Path $ReleasesRoot (
        "current.$($Contract.TargetId)"
    )
    $SelectorItem = Get-Item `
        -LiteralPath $SelectorPath `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -ne $SelectorItem -and
        ($SelectorItem.PSIsContainer -or
            ($SelectorItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        Remove-SwawHarnessControlledPathWithRetry `
            -Path $SelectorPath `
            -ControlledRoot $EntryRoot `
            -Activity 'removing an unsafe Release selector'
    }
    $SelectorPath = Publish-SwawHarnessReleaseSelector `
        -ReleasesRoot $ReleasesRoot `
        -TargetId ([string]$Contract.TargetId) `
        -ReleaseId ([string]$Release.ReleaseId)
    Write-Host "[PUBLISHED] $($Release.ReleaseId)" -ForegroundColor Green
    Write-Output ([pscustomobject][ordered]@{
        ReleaseId = [string]$Release.ReleaseId
        ReleaseRoot = [string]$Release.Root
        SelectorPath = [string]$SelectorPath
    })
} finally {
    $Lock.Dispose()
}
