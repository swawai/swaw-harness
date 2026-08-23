[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ReleaseSafetyTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Release safety test failed: $Message"
    }
}

function New-ReleaseSafetyCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$CacheRoot
    )

    $Item = Get-Item -LiteralPath $SourcePath
    $Sha256 = Get-SwawHarnessFileSha256 -Path $SourcePath
    $CandidateId = Get-SwawHarnessCandidateId `
        -ContractRevision ([string]$Contract.Revision) `
        -TargetId ([string]$Contract.TargetId) `
        -Name ([string]$Contract.ProductBinary) `
        -Length ([long]$Item.Length) `
        -Sha256 $Sha256
    $CandidateRoot = Join-Path $BuildRoot "candidates\$CandidateId"
    [void][IO.Directory]::CreateDirectory($CandidateRoot)
    [IO.File]::Copy(
        $SourcePath,
        (Join-Path $CandidateRoot $Contract.ProductBinary),
        $false
    )
    $CandidatePath = Join-Path $CandidateRoot 'candidate.json'
    $Candidate = [ordered]@{
        schema = $script:SwawHarnessCandidateSchema
        candidateId = $CandidateId
        contractRevision = [string]$Contract.Revision
        targetId = [string]$Contract.TargetId
        artifact = [ordered]@{
            name = [string]$Contract.ProductBinary
            length = [long]$Item.Length
            sha256 = $Sha256
        }
    }
    Write-SwawHarnessTextAtomic `
        -Path $CandidatePath `
        -Content (ConvertTo-SwawHarnessJsonText -Value $Candidate) `
        -ControlledRoot $CacheRoot
    return $CandidatePath
}

function Invoke-ReleaseSafetyPublish {
    param(
        [Parameter(Mandatory = $true)][string]$WindowsRoot,
        [Parameter(Mandatory = $true)][string]$VarRoot,
        [Parameter(Mandatory = $true)][string]$EntryRoot,
        [Parameter(Mandatory = $true)][string]$CandidatePath
    )

    return & (Join-Path $WindowsRoot 'publish.ps1') `
        -VarRoot $VarRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath $CandidatePath |
        Select-Object -Last 1
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $WindowsRoot '_lib\contract.ps1')
. (Join-Path $WindowsRoot '_lib\build\candidate.ps1')
. (Join-Path $WindowsRoot '_lib\release\release.ps1')
. (Join-Path $WindowsRoot '_lib\release\selector.ps1')

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
$TestRoot = Join-Path $RepositoryRoot (
    "var_cache\_test\release-safety-$([Guid]::NewGuid().ToString('N'))"
)
$CacheRoot = Join-Path $TestRoot 'var_cache'
$BuildRoot = Join-Path $CacheRoot (
    'bootstrap\windows\build\x86_64-pc-windows-msvc'
)
$EntryRoot = Join-Path $TestRoot 'var_entry\hello'
$JunctionPath = ''
$Running = $null
$LockedSelector = $null

try {
    foreach ($Directory in @($BuildRoot, $EntryRoot)) {
        [void][IO.Directory]::CreateDirectory($Directory)
    }
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')

    $CandidatePath = New-ReleaseSafetyCandidate `
        -SourcePath (Join-Path $env:SystemRoot 'System32\cmd.exe') `
        -BuildRoot $BuildRoot `
        -Contract $Contract `
        -CacheRoot $CacheRoot
    $InterruptedStage = Join-Path `
        (Join-Path $EntryRoot 'releases') `
        '.publish-11111111111111111111111111111111.tmp'
    [void][IO.Directory]::CreateDirectory($InterruptedStage)
    [IO.File]::WriteAllText(
        (Join-Path $InterruptedStage 'residue.txt'),
        'interrupted'
    )
    $First = Invoke-ReleaseSafetyPublish `
        -WindowsRoot $WindowsRoot `
        -VarRoot $TestRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath $CandidatePath
    Assert-ReleaseSafetyTest `
        -Condition (-not [IO.Directory]::Exists($InterruptedStage)) `
        -Message 'Publish did not clean interrupted Release work'

    $FirstCreated = (Get-Item -LiteralPath $First.ReleaseRoot).CreationTimeUtc
    $FirstAgain = Invoke-ReleaseSafetyPublish `
        -WindowsRoot $WindowsRoot `
        -VarRoot $TestRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath $CandidatePath
    Assert-ReleaseSafetyTest `
        -Condition (
            $First.ReleaseId -ceq $FirstAgain.ReleaseId -and
            (Get-Item -LiteralPath $First.ReleaseRoot).CreationTimeUtc -eq
                $FirstCreated
        ) `
        -Message 'idempotent publication rewrote an immutable Release'

    $FirstExecutable = Join-Path `
        $First.ReleaseRoot `
        $Contract.ProductBinary
    $Running = Start-Process `
        -FilePath $FirstExecutable `
        -ArgumentList @('/d', '/c', 'ping -n 8 127.0.0.1 >nul') `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Milliseconds 400

    $CandidatePath = New-ReleaseSafetyCandidate `
        -SourcePath (Join-Path $env:SystemRoot 'System32\where.exe') `
        -BuildRoot $BuildRoot `
        -Contract $Contract `
        -CacheRoot $CacheRoot
    $SecondCandidatePath = $CandidatePath
    $Second = Invoke-ReleaseSafetyPublish `
        -WindowsRoot $WindowsRoot `
        -VarRoot $TestRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath $CandidatePath
    Assert-ReleaseSafetyTest `
        -Condition (
            -not $Running.HasExited -and
            $First.ReleaseId -cne $Second.ReleaseId -and
            [IO.Directory]::Exists($First.ReleaseRoot)
        ) `
        -Message 'a new Release was not selected beside the running old Release'

    $ReleaseRoot = [string]$Second.ReleaseRoot
    $ReleasesRoot = Split-Path -Path $ReleaseRoot -Parent
    [IO.File]::WriteAllBytes(
        [string]$Second.SelectorPath,
        [byte[]]::new(0)
    )
    [void](Publish-SwawHarnessReleaseSelector `
        -ReleasesRoot $ReleasesRoot `
        -TargetId $Contract.TargetId `
        -ReleaseId $Second.ReleaseId)
    $SelectedAfterEmptySelector = Read-SwawHarnessSelectedRelease `
        -EntryRoot $EntryRoot `
        -Contract $Contract
    Assert-ReleaseSafetyTest `
        -Condition (
            [string]$SelectedAfterEmptySelector.ReleaseId -ceq
                [string]$Second.ReleaseId
        ) `
        -Message 'Publish did not repair an empty Release selector'
    $SelectorBeforeFailure = [IO.File]::ReadAllText(
        [string]$Second.SelectorPath,
        [Text.Encoding]::UTF8
    )
    Assert-ReleaseSafetyTest `
        -Condition (@(
            Get-ChildItem -LiteralPath $ReleasesRoot -Force |
                Where-Object {
                    $_.Name -like '.publish-*.tmp' -or
                    $_.Name -like '.current.*.tmp' -or
                    $_.Name -like '.current.*.backup'
                }
        ).Count -eq 0) `
        -Message 'successful publication left temporary files behind'

    $OversizedArtifact = Join-Path $BuildRoot 'oversized.exe'
    $OversizedStream = [IO.File]::Open(
        $OversizedArtifact,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $OversizedStream.SetLength(512MB + 1)
    } finally {
        $OversizedStream.Dispose()
    }
    $OversizedSha256 = '0' * 64
    $OversizedCandidateId = Get-SwawHarnessCandidateId `
        -ContractRevision ([string]$Contract.Revision) `
        -TargetId ([string]$Contract.TargetId) `
        -Name ([string]$Contract.ProductBinary) `
        -Length (512MB + 1) `
        -Sha256 $OversizedSha256
    $OversizedRoot = Join-Path $BuildRoot (
        "candidates\$OversizedCandidateId"
    )
    [void][IO.Directory]::CreateDirectory($OversizedRoot)
    [IO.File]::Move(
        $OversizedArtifact,
        (Join-Path $OversizedRoot $Contract.ProductBinary)
    )
    $CandidatePath = Join-Path $OversizedRoot 'candidate.json'
    $OversizedCandidate = [ordered]@{
        schema = $script:SwawHarnessCandidateSchema
        candidateId = $OversizedCandidateId
        contractRevision = [string]$Contract.Revision
        targetId = [string]$Contract.TargetId
        artifact = [ordered]@{
            name = [string]$Contract.ProductBinary
            length = 512MB + 1
            sha256 = $OversizedSha256
        }
    }
    Write-SwawHarnessTextAtomic `
        -Path $CandidatePath `
        -Content (ConvertTo-SwawHarnessJsonText -Value $OversizedCandidate) `
        -ControlledRoot $CacheRoot
    $OversizedRejected = $false
    try {
        [void](Invoke-ReleaseSafetyPublish `
            -WindowsRoot $WindowsRoot `
            -VarRoot $TestRoot `
            -EntryRoot $EntryRoot `
            -CandidatePath $CandidatePath)
    } catch {
        $OversizedRejected = $true
    }
    Assert-ReleaseSafetyTest `
        -Condition ($OversizedRejected -and
            [IO.File]::ReadAllText(
                [string]$Second.SelectorPath,
                [Text.Encoding]::UTF8
            ) -ceq $SelectorBeforeFailure) `
        -Message 'an oversized candidate passed or changed the selector'
    [IO.Directory]::Delete($OversizedRoot, $true)

    $JunctionEntryRoot = Join-Path $TestRoot 'var_entry\junction-entry'
    $ExternalReleases = Join-Path $TestRoot 'external-releases'
    [void][IO.Directory]::CreateDirectory($JunctionEntryRoot)
    [void][IO.Directory]::CreateDirectory($ExternalReleases)
    Copy-Item `
        -LiteralPath $ReleaseRoot `
        -Destination (Join-Path $ExternalReleases $Second.ReleaseId) `
        -Recurse
    $JunctionPath = Join-Path $JunctionEntryRoot 'releases'
    [void](New-Item `
        -ItemType Junction `
        -Path $JunctionPath `
        -Target $ExternalReleases)
    $JunctionRejected = $false
    try {
        [void](Read-SwawHarnessRelease `
            -ReleaseRoot (Join-Path $JunctionPath $Second.ReleaseId) `
            -ReleaseId $Second.ReleaseId `
            -Contract $Contract `
            -ReleasesRoot $JunctionPath)
    } catch {
        $JunctionRejected = $_.Exception.Message -like '*regular directory*'
    }
    Assert-ReleaseSafetyTest `
        -Condition $JunctionRejected `
        -Message 'a Release behind a parent junction passed validation'
    [IO.Directory]::Delete($JunctionPath)
    $JunctionPath = ''

    $UnexpectedMember = Join-Path $ReleaseRoot 'unexpected.bin'
    [IO.File]::WriteAllText($UnexpectedMember, 'unexpected')
    $UnexpectedRejected = $false
    try {
        [void](Read-SwawHarnessSelectedRelease `
            -EntryRoot $EntryRoot `
            -Contract $Contract)
    } catch {
        $UnexpectedRejected = $_.Exception.Message -like '*membership*'
    } finally {
        [IO.File]::Delete($UnexpectedMember)
    }
    Assert-ReleaseSafetyTest `
        -Condition $UnexpectedRejected `
        -Message 'a Release with an unexpected member passed validation'

    $OversizedManifestId = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    $OversizedManifestRoot = Join-Path $ReleasesRoot $OversizedManifestId
    Copy-Item -LiteralPath $ReleaseRoot -Destination $OversizedManifestRoot -Recurse
    $ManifestStream = [IO.File]::Open(
        (Join-Path $OversizedManifestRoot 'manifest.json'),
        [IO.FileMode]::Open,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $ManifestStream.SetLength(1MB + 1)
    } finally {
        $ManifestStream.Dispose()
    }
    $ManifestRejected = $false
    try {
        [void](Read-SwawHarnessRelease `
            -ReleaseRoot $OversizedManifestRoot `
            -ReleaseId $OversizedManifestId `
            -Contract $Contract `
            -ReleasesRoot $ReleasesRoot)
    } catch {
        $ManifestRejected = $true
    } finally {
        [IO.Directory]::Delete($OversizedManifestRoot, $true)
    }
    Assert-ReleaseSafetyTest `
        -Condition $ManifestRejected `
        -Message 'an oversized Release manifest passed validation'

    $LockedSelector = [IO.File]::Open(
        [string]$Second.SelectorPath,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::Read
    )
    $AtomicFailureReported = $false
    try {
        [void](Publish-SwawHarnessReleaseSelector `
            -ReleasesRoot $ReleasesRoot `
            -TargetId $Contract.TargetId `
            -ReleaseId ('a' * 64))
    } catch {
        $AtomicFailureReported = $_.Exception.Message -like '*Recovery files*'
    } finally {
        $LockedSelector.Dispose()
        $LockedSelector = $null
    }
    $RecoveryFiles = @(
        Get-ChildItem -LiteralPath $ReleasesRoot -File -Force |
            Where-Object {
                $_.Name -like '.current.*.tmp' -or
                $_.Name -like '.current.*.backup'
            }
    )
    Assert-ReleaseSafetyTest `
        -Condition (
            $AtomicFailureReported -and
            $RecoveryFiles.Count -ge 1 -and
            [IO.File]::ReadAllText(
                [string]$Second.SelectorPath,
                [Text.Encoding]::UTF8
            ) -ceq $SelectorBeforeFailure
        ) `
        -Message 'a failed atomic selector commit lost state or recovery data'
    foreach ($RecoveryFile in $RecoveryFiles) {
        [IO.File]::Delete($RecoveryFile.FullName)
    }

    $ArtifactPath = Join-Path $ReleaseRoot $Contract.ProductBinary
    [IO.File]::WriteAllText($ArtifactPath, 'coherently-tampered-artifact')
    $ManifestPath = Join-Path $ReleaseRoot 'manifest.json'
    $Manifest = [IO.File]::ReadAllText(
        $ManifestPath,
        [Text.Encoding]::UTF8
    ) | ConvertFrom-Json
    $Manifest.artifacts[0].length = (Get-Item -LiteralPath $ArtifactPath).Length
    $Manifest.artifacts[0].sha256 = Get-SwawHarnessFileSha256 `
        -Path $ArtifactPath
    [IO.File]::WriteAllText(
        $ManifestPath,
        (ConvertTo-SwawHarnessJsonText -Value $Manifest),
        [Text.UTF8Encoding]::new($false)
    )
    $StaleIdentityRejected = $false
    try {
        [void](Read-SwawHarnessSelectedRelease `
            -EntryRoot $EntryRoot `
            -Contract $Contract)
    } catch {
        $StaleIdentityRejected = $_.Exception.Message -like '*identity*'
    }
    Assert-ReleaseSafetyTest `
        -Condition $StaleIdentityRejected `
        -Message 'coherent tampering passed under a stale content identity'
    $Repaired = Invoke-ReleaseSafetyPublish `
        -WindowsRoot $WindowsRoot `
        -VarRoot $TestRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath $SecondCandidatePath
    $SelectedAfterRepair = Read-SwawHarnessSelectedRelease `
        -EntryRoot $EntryRoot `
        -Contract $Contract
    Assert-ReleaseSafetyTest `
        -Condition (
            [string]$Repaired.ReleaseId -ceq [string]$Second.ReleaseId -and
            [string]$SelectedAfterRepair.ReleaseId -ceq
                [string]$Second.ReleaseId
        ) `
        -Message 'Publish did not repair a corrupt content-addressed Release'
} finally {
    if ($null -ne $LockedSelector) {
        $LockedSelector.Dispose()
    }
    if ($null -ne $Running -and -not $Running.HasExited) {
        Stop-Process -Id $Running.Id -Force
        $Running.WaitForExit()
    }
    if (-not [string]::IsNullOrWhiteSpace($JunctionPath) -and
        [IO.Directory]::Exists($JunctionPath)) {
        [IO.Directory]::Delete($JunctionPath)
    }
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap Release safety' -ForegroundColor Green
