Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\foundation.ps1')

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
        -Description 'Bootstrap candidate artifact'
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
