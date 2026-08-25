Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\foundation.ps1')
. (Join-Path $PSScriptRoot '..\filesystem.ps1')

$script:SwawHarnessCandidateSchema = 'swaw.harness.bootstrap-candidate/v2'

function Get-SwawHarnessCandidateId {
    param(
        [Parameter(Mandatory = $true)][string]$ContractRevision,
        [Parameter(Mandatory = $true)][string]$TargetId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][long]$Length,
        [Parameter(Mandatory = $true)][string]$Sha256
    )

    $LengthText = $Length.ToString(
        [Globalization.CultureInfo]::InvariantCulture
    )
    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        $script:SwawHarnessCandidateSchema,
        "contract=$ContractRevision",
        "target=$TargetId",
        "artifact=$Name",
        "length=$LengthText",
        "sha256=$Sha256"
    )))
}

function Read-SwawHarnessBootstrapCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$BuildRoot
    )

    $CandidatesRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $BuildRoot 'candidates') `
        -Root $BuildRoot `
        -Activity 'reading a Bootstrap candidate store'
    $Path = Assert-SwawHarnessPathInsideRoot `
        -Path $Path `
        -Root $CandidatesRoot `
        -Activity 'reading a Bootstrap candidate'
    if ([IO.Path]::GetFileName($Path) -cne 'candidate.json') {
        throw "Bootstrap candidate path must end with candidate.json: $Path"
    }
    $CandidateRoot = Split-Path -Path $Path -Parent
    if (-not (Split-Path -Path $CandidateRoot -Parent).Equals(
        $CandidatesRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Bootstrap candidate must be a direct store member: $Path"
    }
    $CandidateId = [IO.Path]::GetFileName($CandidateRoot)
    if ($CandidateId -cnotmatch '^[a-f0-9]{64}$') {
        throw "Bootstrap candidate directory has an invalid identity: $Path"
    }
    $RootItem = Get-Item `
        -LiteralPath $CandidateRoot `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $RootItem -or -not $RootItem.PSIsContainer -or
        ($RootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bootstrap candidate directory is missing or unsafe: $CandidateRoot"
    }

    [string[]]$ExpectedNames = @('candidate.json', $Contract.ProductBinary)
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

    $Candidate = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Bootstrap candidate'
    Assert-SwawHarnessObjectFields `
        -Value $Candidate `
        -Expected @(
            'schema', 'candidateId', 'contractRevision', 'targetId', 'artifact'
        ) `
        -Description 'Bootstrap candidate'
    Assert-SwawHarnessObjectFields `
        -Value $Candidate.artifact `
        -Expected @('name', 'length', 'sha256') `
        -Description 'Bootstrap candidate artifact'

    $ArtifactName = [string]$Candidate.artifact.name
    if ($ArtifactName -cne [string]$Contract.ProductBinary) {
        throw "Bootstrap candidate artifact name is invalid: $Path"
    }
    $ArtifactPath = Resolve-SwawHarnessChildPath `
        -Root $CandidateRoot `
        -RelativePath $ArtifactName `
        -Description 'Bootstrap candidate artifact'
    $Item = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Bootstrap candidate artifact' `
        -MaximumBytes ([long]$Contract.MaximumBytes)
    $Sha256 = ([string]$Candidate.artifact.sha256).Trim().ToLowerInvariant()
    $ComputedCandidateId = Get-SwawHarnessCandidateId `
        -ContractRevision ([string]$Candidate.contractRevision) `
        -TargetId ([string]$Candidate.targetId) `
        -Name $ArtifactName `
        -Length ([long]$Candidate.artifact.length) `
        -Sha256 $Sha256
    if ([string]$Candidate.schema -cne $script:SwawHarnessCandidateSchema -or
        [string]$Candidate.candidateId -cne $CandidateId -or
        $ComputedCandidateId -cne $CandidateId -or
        [string]$Candidate.contractRevision -cne [string]$Contract.Revision -or
        [string]$Candidate.targetId -cne [string]$Contract.TargetId -or
        $ArtifactName -cne [string]$Contract.ProductBinary -or
        [long]$Candidate.artifact.length -ne [long]$Item.Length -or
        $Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-SwawHarnessFileSha256 -Path $ArtifactPath) -cne $Sha256) {
        throw "Bootstrap candidate validation failed: $Path"
    }

    return [pscustomobject][ordered]@{
        Path = $Path
        CandidateId = $CandidateId
        Root = $CandidateRoot
        TargetId = [string]$Contract.TargetId
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
        -TargetId ([string]$Contract.TargetId) `
        -Name ([string]$Contract.ProductBinary) `
        -Length ([long]$Item.Length) `
        -Sha256 $ArtifactSha256
    $CandidatesRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $BuildRoot 'candidates') `
        -Root $BuildRoot `
        -Activity 'publishing a Bootstrap candidate'
    [void][IO.Directory]::CreateDirectory($CandidatesRoot)
    $CandidateRoot = Join-Path $CandidatesRoot $CandidateId
    $CandidatePath = Join-Path $CandidateRoot 'candidate.json'
    if ([IO.Directory]::Exists($CandidateRoot)) {
        try {
            [void](Read-SwawHarnessBootstrapCandidate `
                -Path $CandidatePath `
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
        $Candidate = [ordered]@{
            schema = $script:SwawHarnessCandidateSchema
            candidateId = $CandidateId
            contractRevision = [string]$Contract.Revision
            targetId = [string]$Contract.TargetId
            artifact = [ordered]@{
                name = [string]$Contract.ProductBinary
                length = [long]$Item.Length
                sha256 = $ArtifactSha256
            }
        }
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
            [IO.File]::WriteAllText(
                (Join-Path $StagedRoot 'candidate.json'),
                (ConvertTo-SwawHarnessJsonText -Value $Candidate),
                [Text.UTF8Encoding]::new($false)
            )
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
        -Path $CandidatePath `
        -Contract $Contract `
        -BuildRoot $BuildRoot)
    return $CandidatePath
}
