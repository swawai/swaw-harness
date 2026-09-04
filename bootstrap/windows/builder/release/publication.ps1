Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'release.ps1')
. (Join-Path $PSScriptRoot 'selector.ps1')
. (Join-Path $PSScriptRoot '..\filesystem.ps1')

function Publish-SwawHarnessBootstrapRelease {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object[]]$Contracts,
        [Parameter(Mandatory = $true)][object[]]$Candidates
    )

    $PlatformTargetId = Get-SwawHarnessReleasePlatformTargetId `
        -Contracts $Contracts
    $StageNamePrefix = ".publish-$PlatformTargetId-"
    $StageNamePattern = (
        '^' + [regex]::Escape($StageNamePrefix) +
        '[a-f0-9]{32}\.tmp$'
    )
    if ($Candidates.Count -ne $Contracts.Count) {
        throw 'Bootstrap Release requires one Candidate for every product.'
    }
    $ReleasesRoot = Assert-SwawHarnessPathInsideRoot `
        -Path ([string]$Context.BootstrapReleaseRoot) `
        -Root $Context.DataRepo `
        -Activity 'using the Bootstrap Release store'
    $Artifacts = [Collections.Generic.List[object]]::new()
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $Contract = $Contracts[$Index]
        $Candidate = $Candidates[$Index]
        $Name = [string]$Candidate.Name
        $Length = [long]$Candidate.Length
        $Sha256 = ([string]$Candidate.Sha256).Trim().ToLowerInvariant()
        if ([string]$Candidate.PlatformTargetId -cne $PlatformTargetId -or
            $Name -cne [string]$Contract.ProductBinary -or
            $Length -le 0 -or
            $Length -gt [long]$Contract.MaximumBytes -or
            $Sha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Candidate does not satisfy its Bootstrap Release contract.'
        }
        $CandidatePath = Assert-SwawHarnessPathInsideRoot `
            -Path ([string]$Candidate.ArtifactPath) `
            -Root $Context.BuildRoot `
            -Activity 'reading a Bootstrap Release candidate artifact'
        $Item = Assert-SwawHarnessRegularFile `
            -Path $CandidatePath `
            -Description 'Bootstrap Release candidate artifact' `
            -MaximumBytes ([long]$Contract.MaximumBytes)
        if ([long]$Item.Length -ne $Length -or
            (Get-SwawHarnessFileSha256 -Path $CandidatePath) -cne $Sha256) {
            throw 'Candidate does not satisfy its Bootstrap Release contract.'
        }
        $Artifacts.Add([pscustomobject][ordered]@{
            Name = $Name
            Length = $Length
            Sha256 = $Sha256
            Path = $CandidatePath
        })
    }

    $ReleaseId = Get-SwawHarnessReleaseId `
        -PlatformTargetId $PlatformTargetId `
        -Artifacts $Artifacts.ToArray()
    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "publish-bootstrap-$PlatformTargetId.lock"
        )) `
        -ControlledRoot $Context.DataRepo `
        -TimeoutSeconds 1800
    try {
        [void][IO.Directory]::CreateDirectory($ReleasesRoot)
        [void](Assert-SwawHarnessControlledRoot `
            -Root $ReleasesRoot `
            -Description 'Bootstrap Release store')
        foreach ($WorkItem in Get-ChildItem -LiteralPath $ReleasesRoot -Force) {
            if ([string]$WorkItem.Name -cmatch $StageNamePattern) {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path ([string]$WorkItem.FullName) `
                    -ControlledRoot $ReleasesRoot `
                    -Activity 'cleaning interrupted Bootstrap Release publication'
            }
        }

        $ReleaseRoot = Join-Path $ReleasesRoot $ReleaseId
        $Release = $null
        if (Test-SwawHarnessPathExists -Path $ReleaseRoot) {
            try {
                $Release = Read-SwawHarnessRelease `
                    -ReleaseRoot $ReleaseRoot `
                    -ReleaseId $ReleaseId `
                    -Contracts $Contracts `
                    -ReleasesRoot $ReleasesRoot
            } catch {
                $Release = $null
            }
        }
        if ($null -eq $Release) {
            $StageParent = Join-Path $ReleasesRoot (
                $StageNamePrefix + [Guid]::NewGuid().ToString('N') + '.tmp'
            )
            $StageRoot = Join-Path $StageParent $ReleaseId
            [void][IO.Directory]::CreateDirectory($StageRoot)
            try {
                $ManifestArtifacts = [Collections.Generic.List[object]]::new()
                foreach ($Artifact in $Artifacts) {
                    $Destination = Resolve-SwawHarnessChildPath `
                        -Root $StageRoot `
                        -RelativePath ([string]$Artifact.Name) `
                        -Description 'staged Bootstrap Release artifact'
                    [IO.File]::Copy([string]$Artifact.Path, $Destination, $false)
                    $StagedItem = Assert-SwawHarnessRegularFile `
                        -Path $Destination `
                        -Description 'staged Bootstrap Release artifact' `
                        -MaximumBytes ([long]$Artifact.Length)
                    if ([long]$StagedItem.Length -ne [long]$Artifact.Length -or
                        (Get-SwawHarnessFileSha256 -Path $Destination) -cne
                            [string]$Artifact.Sha256) {
                        throw "Staged Release artifact is corrupt: $Destination"
                    }
                    $ManifestArtifacts.Add([ordered]@{
                        name = [string]$Artifact.Name
                        length = [long]$Artifact.Length
                        sha256 = [string]$Artifact.Sha256
                    })
                }
                $Manifest = [ordered]@{
                    schema = $script:SwawHarnessReleaseSchema
                    releaseId = $ReleaseId
                    platformTargetId = $PlatformTargetId
                    artifacts = $ManifestArtifacts.ToArray()
                }
                [IO.File]::WriteAllText(
                    (Join-Path $StageRoot 'manifest.json'),
                    (ConvertTo-SwawHarnessJsonText -Value $Manifest),
                    [Text.UTF8Encoding]::new($false)
                )
                [void](Read-SwawHarnessRelease `
                    -ReleaseRoot $StageRoot `
                    -ReleaseId $ReleaseId `
                    -Contracts $Contracts `
                    -ReleasesRoot $ReleasesRoot)
                if (Test-SwawHarnessPathExists -Path $ReleaseRoot) {
                    Remove-SwawHarnessControlledPathWithRetry `
                        -Path $ReleaseRoot `
                        -ControlledRoot $ReleasesRoot `
                        -Activity 'removing a corrupt Bootstrap Release'
                }
                [IO.Directory]::Move($StageRoot, $ReleaseRoot)
            } finally {
                if (Test-SwawHarnessPathExists -Path $StageParent) {
                    Remove-SwawHarnessControlledPathWithRetry `
                        -Path $StageParent `
                        -ControlledRoot $ReleasesRoot `
                        -Activity 'cleaning Bootstrap Release publication work'
                }
            }
        }

        $Release = Read-SwawHarnessRelease `
            -ReleaseRoot $ReleaseRoot `
            -ReleaseId $ReleaseId `
            -Contracts $Contracts `
            -ReleasesRoot $ReleasesRoot
        $SelectorPath = Join-Path $ReleasesRoot "current.$PlatformTargetId"
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
                -Activity 'removing an unsafe Bootstrap Release selector'
        }
        $SelectorPath = Publish-SwawHarnessReleaseSelector `
            -ReleasesRoot $ReleasesRoot `
            -PlatformTargetId $PlatformTargetId `
            -ReleaseId $ReleaseId
        Write-Host "[PUBLISHED] Bootstrap Release $ReleaseId" `
            -ForegroundColor Green
        return [pscustomobject][ordered]@{
            ReleaseId = $Release.ReleaseId
            PlatformTargetId = $Release.PlatformTargetId
            Root = $Release.Root
            ManifestPath = $Release.ManifestPath
            Artifacts = $Release.Artifacts
            SelectorPath = $SelectorPath
        }
    } finally {
        $Lock.Dispose()
    }
}
