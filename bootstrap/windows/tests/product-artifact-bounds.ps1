[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ProductArtifactBoundsTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Product artifact bounds test failed: $Message"
    }
}

function Test-ProductArtifactBoundsRejection {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    try {
        & $Action
        return $false
    } catch {
        return (
            $_.Exception.Message -like '*bounded regular file*' -or
            $_.Exception.Message -like
                '*does not satisfy its Bootstrap Release contract*'
        )
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $WindowsRoot 'builder\build\candidate.ps1')
. (Join-Path $WindowsRoot 'builder\release\publication.ps1')

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
$WindowsBuildRoot = Join-Path $TestRoot 'windows.build'
$BuildRoot = Join-Path $WindowsBuildRoot 'bounds-test'
$LockRoot = Join-Path $TestRoot 'windows.locks'
$ReleasesRoot = Join-Path $TestRoot 'bounds-test.release'
$MaximumBytes = 64KB
$OversizedLength = $MaximumBytes + 1
$Contract = [pscustomobject][ordered]@{
    Revision = '1' * 64
    PlatformTargetId = 'x86_64-pc-windows-msvc'
    ProductBinary = 'bounds-test.exe'
    MaximumBytes = $MaximumBytes
}
$Context = [pscustomobject][ordered]@{
    DataRepo = $TestRoot
    BuildRoot = $WindowsBuildRoot
    BootstrapReleaseRoot = $ReleasesRoot
    LockRoot = $LockRoot
}

try {
    foreach ($Directory in @(
        $BuildRoot,
        $LockRoot,
        $ReleasesRoot
    )) {
        [void][IO.Directory]::CreateDirectory($Directory)
    }

    $SourcePath = Join-Path $BuildRoot 'oversized-source.exe'
    $SourceStream = [IO.File]::Open(
        $SourcePath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $SourceStream.SetLength($OversizedLength)
    } finally {
        $SourceStream.Dispose()
    }
    $Sha256 = Get-SwawHarnessFileSha256 -Path $SourcePath

    $CandidatePublisherRejected = Test-ProductArtifactBoundsRejection {
        [void](Publish-SwawHarnessBootstrapCandidate `
            -ArtifactPath $SourcePath `
            -Contract $Contract `
            -BuildRoot $BuildRoot `
            -ControlledRoot $WindowsBuildRoot)
    }
    Assert-ProductArtifactBoundsTest `
        -Condition $CandidatePublisherRejected `
        -Message 'Candidate publication accepted product maximum + 1 byte'

    $CandidateId = Get-SwawHarnessCandidateId `
        -ContractRevision $Contract.Revision `
        -PlatformTargetId $Contract.PlatformTargetId `
        -Name $Contract.ProductBinary `
        -Length $OversizedLength `
        -Sha256 $Sha256
    $CandidateRoot = Join-Path $BuildRoot "candidates\$CandidateId"
    [void][IO.Directory]::CreateDirectory($CandidateRoot)
    [IO.File]::Copy(
        $SourcePath,
        (Join-Path $CandidateRoot $Contract.ProductBinary),
        $false
    )
    $CandidateReaderRejected = Test-ProductArtifactBoundsRejection {
        [void](Read-SwawHarnessBootstrapCandidate `
            -CandidateRoot $CandidateRoot `
            -Contract $Contract `
            -BuildRoot $BuildRoot)
    }
    Assert-ProductArtifactBoundsTest `
        -Condition $CandidateReaderRejected `
        -Message 'Candidate reader accepted product maximum + 1 byte'

    $Candidate = [pscustomobject][ordered]@{
        PlatformTargetId = $Contract.PlatformTargetId
        Name = $Contract.ProductBinary
        ArtifactPath = $SourcePath
        Length = $OversizedLength
        Sha256 = $Sha256
    }
    $ReleasePublisherRejected = Test-ProductArtifactBoundsRejection {
        [void](Publish-SwawHarnessBootstrapRelease `
            -Context $Context `
            -Contracts @($Contract) `
            -Candidates @($Candidate))
    }
    Assert-ProductArtifactBoundsTest `
        -Condition $ReleasePublisherRejected `
        -Message 'Release staging accepted product maximum + 1 byte'

    $ActualSizeRejected = Test-ProductArtifactBoundsRejection {
        $DeclaredWithinLimit = [pscustomobject][ordered]@{
            PlatformTargetId = $Contract.PlatformTargetId
            Name = $Contract.ProductBinary
            ArtifactPath = $SourcePath
            Length = $MaximumBytes
            Sha256 = $Sha256
        }
        [void](Publish-SwawHarnessBootstrapRelease `
            -Context $Context `
            -Contracts @($Contract) `
            -Candidates @($DeclaredWithinLimit))
    }
    Assert-ProductArtifactBoundsTest `
        -Condition $ActualSizeRejected `
        -Message 'Release staging trusted a bounded declared length over the file'

    $MismatchedSourcePath = Join-Path $BuildRoot 'mismatched-source.exe'
    [IO.File]::WriteAllBytes($MismatchedSourcePath, [byte[]](1, 2))
    $MismatchedSha256 = Get-SwawHarnessFileSha256 `
        -Path $MismatchedSourcePath
    $ActualLengthRejected = Test-ProductArtifactBoundsRejection {
        $MismatchedCandidate = [pscustomobject][ordered]@{
            PlatformTargetId = $Contract.PlatformTargetId
            Name = $Contract.ProductBinary
            ArtifactPath = $MismatchedSourcePath
            Length = 1
            Sha256 = $MismatchedSha256
        }
        [void](Publish-SwawHarnessBootstrapRelease `
            -Context $Context `
            -Contracts @($Contract) `
            -Candidates @($MismatchedCandidate))
    }
    Assert-ProductArtifactBoundsTest `
        -Condition $ActualLengthRejected `
        -Message 'Release staging accepted a mismatched actual artifact length'

    $ReleaseId = Get-SwawHarnessReleaseId `
        -PlatformTargetId $Contract.PlatformTargetId `
        -Artifacts @([pscustomobject]@{
            Name = $Contract.ProductBinary
            Length = $OversizedLength
            Sha256 = $Sha256
        })
    $ReleaseRoot = Join-Path $ReleasesRoot $ReleaseId
    [void][IO.Directory]::CreateDirectory($ReleaseRoot)
    [IO.File]::Copy(
        $SourcePath,
        (Join-Path $ReleaseRoot $Contract.ProductBinary),
        $false
    )
    $ReleaseManifest = [ordered]@{
        schema = $script:SwawHarnessReleaseSchema
        releaseId = $ReleaseId
        platformTargetId = $Contract.PlatformTargetId
        artifacts = @([ordered]@{
            name = $Contract.ProductBinary
            length = $OversizedLength
            sha256 = $Sha256
        })
    }
    [IO.File]::WriteAllText(
        (Join-Path $ReleaseRoot 'manifest.json'),
        (ConvertTo-SwawHarnessJsonText -Value $ReleaseManifest),
        [Text.UTF8Encoding]::new($false)
    )
    $ReleaseReaderRejected = Test-ProductArtifactBoundsRejection {
        [void](Read-SwawHarnessRelease `
            -ReleaseRoot $ReleaseRoot `
            -ReleaseId $ReleaseId `
            -Contracts @($Contract) `
            -ReleasesRoot $ReleasesRoot)
    }
    Assert-ProductArtifactBoundsTest `
        -Condition $ReleaseReaderRejected `
        -Message 'Release reader accepted product maximum + 1 byte'

    Assert-ProductArtifactBoundsTest `
        -Condition (
            (Get-Item -LiteralPath $SourcePath).Length -eq
                $OversizedLength -and
            $OversizedLength -lt 1MB
        ) `
        -Message 'test artifact is not the intended small boundary case'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows product artifact bounds' -ForegroundColor Green
