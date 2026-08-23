[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$VarRoot,
    [Parameter(Mandatory = $true)][string]$CargoPath,
    [Collections.IDictionary]$EnvironmentVariables = @{},
    [string[]]$UnsetEnvironmentVariables = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '_lib\contract.ps1')
. (Join-Path $PSScriptRoot '_lib\process.ps1')
. (Join-Path $PSScriptRoot '_lib\build\candidate.ps1')
. (Join-Path $PSScriptRoot '_lib\filesystem.ps1')

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$ContractPath = Join-Path $PSScriptRoot 'contract.json'
$Contract = Read-SwawHarnessWindowsBootstrapContract -Path $ContractPath
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
$BuildRoot = Assert-SwawHarnessPathInsideRoot `
    -Path $BuildRoot `
    -Root $CacheRoot `
    -Activity 'building the Windows candidate'
[void][IO.Directory]::CreateDirectory($BuildRoot)

$CargoPath = Get-SwawHarnessFullPath -Path $CargoPath
[void](Assert-SwawHarnessRegularFile `
    -Path $CargoPath `
    -Description 'Cargo executable')
$WorkspaceManifest = Join-Path $RepositoryRoot 'source\Cargo.toml'
[void](Assert-SwawHarnessRegularFile `
    -Path $WorkspaceManifest `
    -Description 'Rust workspace manifest' `
    -MaximumBytes 1048576)

$BuildLock = Enter-SwawHarnessFileLock `
    -Path (Join-Path $CacheRoot (
        "bootstrap\windows\locks\build-$($Contract.TargetId).lock"
    )) `
    -ControlledRoot $CacheRoot `
    -TimeoutSeconds 1800
try {
    foreach ($WorkItem in Get-ChildItem -LiteralPath $BuildRoot -Force) {
        if ([string]$WorkItem.Name -cmatch
            '^\.candidate-[a-f0-9]{32}\.tmp$') {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path ([string]$WorkItem.FullName) `
                -ControlledRoot $CacheRoot `
                -Activity 'cleaning interrupted candidate work'
        }
    }
    $CargoTargetRoot = Join-Path $BuildRoot 'cargo-target'
    $Arguments = @(
        'build',
        '--locked',
        '--release',
        '--package',
        $Contract.ProductPackage,
        '--manifest-path',
        $WorkspaceManifest,
        '--target',
        $Contract.TargetId,
        '--target-dir',
        $CargoTargetRoot
    )
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $CargoPath `
        -Arguments $Arguments `
        -WorkingDirectory (Join-Path $RepositoryRoot 'source') `
        -EnvironmentVariables $EnvironmentVariables `
        -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
        -TimeoutSeconds 1800
    if ($Result.ExitCode -ne 0) {
        throw (
            "Cargo build failed with exit code $($Result.ExitCode). " +
            "$($Result.Error) $($Result.Output)"
        ).Trim()
    }

    $ArtifactPath = Join-Path $CargoTargetRoot (
        "$($Contract.TargetId)\release\$($Contract.ProductBinary)"
    )
    $Item = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Built Windows candidate'
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
                -ControlledRoot $CacheRoot `
                -Activity 'removing a corrupt Bootstrap candidate'
        }
    } elseif (Test-SwawHarnessPathExists -Path $CandidateRoot) {
        Remove-SwawHarnessControlledPathWithRetry `
            -Path $CandidateRoot `
            -ControlledRoot $CacheRoot `
            -Activity 'removing an unsafe Bootstrap candidate'
    }

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
                -Description 'Staged Bootstrap candidate artifact'
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
            if ([IO.Directory]::Exists($WorkParent)) {
                [IO.Directory]::Delete($WorkParent, $true)
            }
        }
    }
    [void](Read-SwawHarnessBootstrapCandidate `
        -Path $CandidatePath `
        -Contract $Contract `
        -BuildRoot $BuildRoot)
    Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
    Write-Output $CandidatePath
} finally {
    $BuildLock.Dispose()
}
