Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\foundation.ps1')
. (Join-Path $PSScriptRoot '..\filesystem.ps1')

$script:SwawHarnessCandidateIdentityVersion = `
    'swaw.harness.bootstrap-candidate/v4'

function Get-SwawHarnessCandidateId {
    param(
        [Parameter(Mandatory = $true)][string]$ContractRevision,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][long]$Length,
        [Parameter(Mandatory = $true)][string]$Sha256
    )

    $LengthText = $Length.ToString(
        [Globalization.CultureInfo]::InvariantCulture
    )
    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        $script:SwawHarnessCandidateIdentityVersion,
        "contract=$ContractRevision",
        "target=$PlatformTargetId",
        "artifact=$Name",
        "length=$LengthText",
        "sha256=$Sha256"
    )))
}

function Enter-SwawHarnessCandidateLifecycleLock {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId,
        [IO.FileStream]$ExistingLock = $null
    )

    $LockPath = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.LockRoot (
            "bootstrap-$PlatformTargetId.lock"
        )) `
        -Root $Context.DataRepo `
        -Activity 'coordinating the Candidate lifecycle'
    if ($null -eq $ExistingLock) {
        return [pscustomobject][ordered]@{
            Stream = Enter-SwawHarnessFileLock `
                -Path $LockPath `
                -ControlledRoot $Context.DataRepo `
                -TimeoutSeconds 7200
            OwnsStream = $true
        }
    }

    $LockIsOpen = $false
    try {
        $LockIsOpen = -not $ExistingLock.SafeFileHandle.IsClosed -and
            -not $ExistingLock.SafeFileHandle.IsInvalid
    } catch {
        $LockIsOpen = $false
    }
    if (-not $LockIsOpen -or
        -not ([IO.Path]::GetFullPath($ExistingLock.Name)).Equals(
            $LockPath,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Candidate lifecycle lock is invalid for: $PlatformTargetId"
    }
    return [pscustomobject][ordered]@{
        Stream = $ExistingLock
        OwnsStream = $false
    }
}

function Exit-SwawHarnessCandidateLifecycleLock {
    param([Parameter(Mandatory = $true)][object]$LockHandle)

    if ([bool]$LockHandle.OwnsStream) {
        $LockHandle.Stream.Dispose()
    }
}

function Get-SwawHarnessCandidateConsumerLockPath {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    return Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.LockRoot (
            "candidate-consumers-$PlatformTargetId.lock"
        )) `
        -Root $Context.DataRepo `
        -Activity 'coordinating Candidate consumers'
}

function Enter-SwawHarnessCandidateConsumerLock {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId,
        [int]$TimeoutSeconds = 7200
    )

    $Path = Get-SwawHarnessCandidateConsumerLockPath `
        -Context $Context `
        -PlatformTargetId $PlatformTargetId
    [void][IO.Directory]::CreateDirectory((Split-Path -Path $Path -Parent))
    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            return [IO.FileStream]::new(
                $Path,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::ReadWrite
            )
        } catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $Deadline) {
                throw "Timed out waiting for Candidate consumers: $Path"
            }
            Start-Sleep -Milliseconds 100
        }
    } while ($true)
}

function Enter-SwawHarnessCandidateCleanupLock {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    $Path = Get-SwawHarnessCandidateConsumerLockPath `
        -Context $Context `
        -PlatformTargetId $PlatformTargetId
    [void][IO.Directory]::CreateDirectory((Split-Path -Path $Path -Parent))
    try {
        return [IO.FileStream]::new(
            $Path,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    } catch [IO.IOException] {
        return $null
    }
}

function Read-SwawHarnessBootstrapCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateRoot,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$BuildRoot
    )

    $CandidatesRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $BuildRoot 'candidates') `
        -Root $BuildRoot `
        -Activity 'reading a Bootstrap candidate store'
    $CandidateRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $CandidateRoot `
        -Root $CandidatesRoot `
        -Activity 'reading a Bootstrap candidate'
    if (-not (Split-Path -Path $CandidateRoot -Parent).Equals(
        $CandidatesRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Bootstrap candidate must be a direct store member: $CandidateRoot"
    }
    $CandidateId = [IO.Path]::GetFileName($CandidateRoot)
    if ($CandidateId -cnotmatch '^[a-f0-9]{64}$') {
        throw "Bootstrap candidate directory has an invalid identity: $CandidateRoot"
    }
    $RootItem = Get-Item `
        -LiteralPath $CandidateRoot `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $RootItem -or -not $RootItem.PSIsContainer -or
        ($RootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bootstrap candidate directory is missing or unsafe: $CandidateRoot"
    }

    [string[]]$ExpectedNames = @([string]$Contract.ProductBinary)
    [string[]]$ActualNames = @(
        Get-ChildItem -LiteralPath $CandidateRoot -Force |
            ForEach-Object { [string]$_.Name }
    )
    if ($ActualNames.Count -ne $ExpectedNames.Count) {
        throw "Bootstrap candidate membership is invalid: $CandidateRoot"
    }
    foreach ($Name in $ExpectedNames) {
        if ($ActualNames -cnotcontains $Name) {
            throw "Bootstrap candidate membership is invalid: $CandidateRoot"
        }
    }

    $ArtifactName = [string]$Contract.ProductBinary
    $ArtifactPath = Resolve-SwawHarnessChildPath `
        -Root $CandidateRoot `
        -RelativePath $ArtifactName `
        -Description 'Bootstrap candidate artifact'
    $Item = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Bootstrap candidate artifact' `
        -MaximumBytes ([long]$Contract.MaximumBytes)
    $Sha256 = Get-SwawHarnessFileSha256 -Path $ArtifactPath
    $ComputedCandidateId = Get-SwawHarnessCandidateId `
        -ContractRevision ([string]$Contract.Revision) `
        -PlatformTargetId ([string]$Contract.PlatformTargetId) `
        -Name $ArtifactName `
        -Length ([long]$Item.Length) `
        -Sha256 $Sha256
    if ($ComputedCandidateId -cne $CandidateId) {
        throw "Bootstrap candidate validation failed: $CandidateRoot"
    }

    return [pscustomobject][ordered]@{
        CandidateId = $CandidateId
        Root = $CandidateRoot
        PlatformTargetId = [string]$Contract.PlatformTargetId
        Name = [string]$Contract.ProductBinary
        ArtifactPath = $ArtifactPath
        Length = [long]$Item.Length
        Sha256 = $Sha256
    }
}

function Publish-SwawHarnessBootstrapCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $BuildRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $BuildRoot `
        -Root $ControlledRoot `
        -Activity 'publishing a Bootstrap candidate'
    [void][IO.Directory]::CreateDirectory($BuildRoot)
    foreach ($WorkItem in Get-ChildItem -LiteralPath $BuildRoot -Force) {
        if ([string]$WorkItem.Name -cmatch
            '^\.candidate-[a-f0-9]{32}\.tmp$') {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path ([string]$WorkItem.FullName) `
                -ControlledRoot $ControlledRoot `
                -Activity 'cleaning interrupted candidate work'
        }
    }

    $Item = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Built Windows candidate' `
        -MaximumBytes ([long]$Contract.MaximumBytes)
    $ArtifactSha256 = Get-SwawHarnessFileSha256 -Path $ArtifactPath
    $CandidateId = Get-SwawHarnessCandidateId `
        -ContractRevision ([string]$Contract.Revision) `
        -PlatformTargetId ([string]$Contract.PlatformTargetId) `
        -Name ([string]$Contract.ProductBinary) `
        -Length ([long]$Item.Length) `
        -Sha256 $ArtifactSha256
    $CandidatesRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $BuildRoot 'candidates') `
        -Root $BuildRoot `
        -Activity 'publishing a Bootstrap candidate'
    [void][IO.Directory]::CreateDirectory($CandidatesRoot)
    $CandidateRoot = Join-Path $CandidatesRoot $CandidateId
    if ([IO.Directory]::Exists($CandidateRoot)) {
        try {
            [void](Read-SwawHarnessBootstrapCandidate `
                -CandidateRoot $CandidateRoot `
                -Contract $Contract `
                -BuildRoot $BuildRoot)
        } catch {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path $CandidateRoot `
                -ControlledRoot $ControlledRoot `
                -Activity 'removing a corrupt Bootstrap candidate'
        }
    } elseif (Test-SwawHarnessPathExists -Path $CandidateRoot) {
        Remove-SwawHarnessControlledPathWithRetry `
            -Path $CandidateRoot `
            -ControlledRoot $ControlledRoot `
            -Activity 'removing an unsafe Bootstrap candidate'
    }

    if (-not [IO.Directory]::Exists($CandidateRoot)) {
        $WorkParent = Join-Path $BuildRoot (
            ".candidate-$([Guid]::NewGuid().ToString('N')).tmp"
        )
        $StagedRoot = Join-Path $WorkParent $CandidateId
        [void][IO.Directory]::CreateDirectory($StagedRoot)
        try {
            $StagedArtifact = Join-Path $StagedRoot $Contract.ProductBinary
            [IO.File]::Copy($ArtifactPath, $StagedArtifact, $false)
            $StagedItem = Assert-SwawHarnessRegularFile `
                -Path $StagedArtifact `
                -Description 'Staged Bootstrap candidate artifact' `
                -MaximumBytes ([long]$Contract.MaximumBytes)
            if ([long]$StagedItem.Length -ne [long]$Item.Length -or
                (Get-SwawHarnessFileSha256 -Path $StagedArtifact) -cne
                    $ArtifactSha256) {
                throw 'Staged Bootstrap candidate artifact is corrupt.'
            }
            [IO.Directory]::Move($StagedRoot, $CandidateRoot)
        } finally {
            if (Test-SwawHarnessPathExists -Path $WorkParent) {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path $WorkParent `
                    -ControlledRoot $ControlledRoot `
                    -Activity 'cleaning candidate publication work'
            }
        }
    }

    [void](Read-SwawHarnessBootstrapCandidate `
        -CandidateRoot $CandidateRoot `
        -Contract $Contract `
        -BuildRoot $BuildRoot)
    return $CandidateRoot
}
