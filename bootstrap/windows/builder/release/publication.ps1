Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'release.ps1')
. (Join-Path $PSScriptRoot 'selector.ps1')
. (Join-Path $PSScriptRoot '..\filesystem.ps1')

function Publish-SwawHarnessRelease {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$Candidate,
        [Parameter(Mandatory = $true)][string]$ReleasesRoot,
        [Parameter(Mandatory = $true)][string]$LockName
    )

    $ReleasesRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $ReleasesRoot `
        -Root $Context.DataRoot `
        -Activity 'using a Release store'
    $CandidateName = [string]$Candidate.Name
    $CandidateLength = [long]$Candidate.Length
    $CandidateSha256 = ([string]$Candidate.Sha256).Trim().ToLowerInvariant()
    if ([string]$Candidate.TargetId -cne [string]$Contract.TargetId -or
        $CandidateName -cne [string]$Contract.ProductBinary -or
        $CandidateLength -le 0 -or
        $CandidateLength -gt [long]$Contract.MaximumBytes -or
        $CandidateSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Candidate does not satisfy the product Release contract.'
    }
    $CandidateArtifactPath = Assert-SwawHarnessPathInsideRoot `
        -Path ([string]$Candidate.ArtifactPath) `
        -Root $Context.BootstrapWindowsCacheRoot `
        -Activity 'reading a product candidate artifact'
    $CandidateArtifact = Assert-SwawHarnessRegularFile `
        -Path $CandidateArtifactPath `
        -Description 'Product candidate artifact' `
        -MaximumBytes ([long]$Contract.MaximumBytes)
    if ([long]$CandidateArtifact.Length -ne $CandidateLength) {
        throw 'Candidate does not satisfy the product Release contract.'
    }
    [void][IO.Directory]::CreateDirectory($ReleasesRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $ReleasesRoot `
        -Description 'Release store')
    $ReleaseId = Get-SwawHarnessReleaseId `
        -TargetId ([string]$Candidate.TargetId) `
        -Name $CandidateName `
        -Length $CandidateLength `
        -Sha256 $CandidateSha256

    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot $LockName) `
        -ControlledRoot $Context.BootstrapWindowsRoot
    try {
        foreach ($WorkItem in Get-ChildItem -LiteralPath $ReleasesRoot -Force) {
            if ([string]$WorkItem.Name -cmatch
                '^\.publish-[a-f0-9]{32}\.tmp$') {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path ([string]$WorkItem.FullName) `
                    -ControlledRoot $ReleasesRoot `
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
                $Destination = Resolve-SwawHarnessChildPath `
                    -Root $StageRoot `
                    -RelativePath $CandidateName `
                    -Description 'Staged Release artifact'
                [IO.File]::Copy($CandidateArtifactPath, $Destination, $false)
                $Item = Assert-SwawHarnessRegularFile `
                    -Path $Destination `
                    -Description 'Staged Release artifact' `
                    -MaximumBytes ([long]$Contract.MaximumBytes)
                $Hash = Get-SwawHarnessFileSha256 -Path $Destination
                if ([long]$Item.Length -ne $CandidateLength -or
                    $Hash -cne $CandidateSha256) {
                    throw "Staged Release artifact is corrupt: $Destination"
                }
                $Manifest = [ordered]@{
                    schema = $script:SwawHarnessReleaseSchema
                    releaseId = [string]$ReleaseId
                    targetId = [string]$Contract.TargetId
                    artifacts = @([ordered]@{
                        name = $CandidateName
                        length = $CandidateLength
                        sha256 = $CandidateSha256
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
                        -ControlledRoot $ReleasesRoot `
                        -Activity 'removing a corrupt content-addressed Release'
                }
                [IO.Directory]::Move($StageRoot, $ReleaseRoot)
            } finally {
                if (Test-SwawHarnessPathExists -Path $StageParent) {
                    Remove-SwawHarnessControlledPathWithRetry `
                        -Path $StageParent `
                        -ControlledRoot $ReleasesRoot `
                        -Activity 'cleaning Release publication work'
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
                -ControlledRoot $ReleasesRoot `
                -Activity 'removing an unsafe Release selector'
        }
        $SelectorPath = Publish-SwawHarnessReleaseSelector `
            -ReleasesRoot $ReleasesRoot `
            -TargetId ([string]$Contract.TargetId) `
            -ReleaseId ([string]$Release.ReleaseId)
        return [pscustomobject][ordered]@{
            ReleaseId = [string]$Release.ReleaseId
            ReleaseRoot = [string]$Release.Root
            SelectorPath = [string]$SelectorPath
        }
    } finally {
        $Lock.Dispose()
    }
}
