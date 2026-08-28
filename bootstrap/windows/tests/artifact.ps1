[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ArtifactTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Artifact test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $WindowsRoot 'toolchain\download-cache.ps1')
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRoot = Resolve-SwawHarnessWindowsTestDataRoot `
    -DataRoot $DataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot `
    -DataRoot $DataRoot `
    -Name 'artifact'
$OwnerRoot = Join-Path $TestRoot 'bootstrap.windows'
$CacheRoot = Join-Path $TestRoot 'bootstrap.windows.cache'
$SourceRoot = Join-Path $TestRoot 'source'
$JunctionPath = ''

try {
    [void][IO.Directory]::CreateDirectory($OwnerRoot)
    [void][IO.Directory]::CreateDirectory($CacheRoot)
    [void][IO.Directory]::CreateDirectory($SourceRoot)
    $Context = [pscustomobject]@{
        BootstrapWindowsRoot = $OwnerRoot
        BootstrapWindowsCacheRoot = $CacheRoot
        DownloadRoot = Join-Path $CacheRoot 'downloads'
        LockRoot = Join-Path $OwnerRoot 'locks'
    }
    [byte[]]$OversizedBytes = [byte[]]::new(33)
    $BoundedStream = [IO.MemoryStream]::new($OversizedBytes)
    $BoundedPath = Join-Path $CacheRoot 'bounded-stream.bin'
    $BoundedRejected = $false
    try {
        [void](Copy-SwawHarnessBoundedStream `
            -InputStream $BoundedStream `
            -Destination $BoundedPath `
            -MaximumBytes 32)
    } catch {
        $BoundedRejected = $_.Exception.Message -like '*byte budget*'
    } finally {
        $BoundedStream.Dispose()
    }
    $BoundedLength = (Get-Item -LiteralPath $BoundedPath).Length
    [IO.File]::Delete($BoundedPath)
    Assert-ArtifactTest `
        -Condition ($BoundedRejected -and $BoundedLength -le 32) `
        -Message 'bounded stream wrote beyond its download budget'

    $OversizedSource = Join-Path $SourceRoot 'oversized.bin'
    [IO.File]::WriteAllBytes($OversizedSource, $OversizedBytes)
    $OversizedDestination = Join-Path $CacheRoot 'oversized.bin'
    $OversizedRejected = $false
    try {
        Invoke-SwawHarnessDownload `
            -Source $OversizedSource `
            -Destination $OversizedDestination `
            -ControlledRoot $CacheRoot `
            -MaximumBytes 32
    } catch {
        $OversizedRejected = $true
    }
    Assert-ArtifactTest `
        -Condition ($OversizedRejected -and
            -not [IO.File]::Exists($OversizedDestination)) `
        -Message 'oversized local artifact was copied into the cache'

    $Source = Join-Path $SourceRoot 'artifact.bin'
    [IO.File]::WriteAllText(
        $Source,
        'verified artifact bytes',
        [Text.UTF8Encoding]::new($false)
    )
    $Length = (Get-Item -LiteralPath $Source).Length
    $Sha256 = Get-SwawHarnessFileSha256 -Path $Source
    $Cached = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source $Source `
        -ExpectedLength $Length `
        -ExpectedSha256 $Sha256 `
        -Description 'test artifact'
    [IO.File]::Delete($Source)
    $Offline = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source 'https://unreachable.invalid/artifact.bin' `
        -ExpectedLength $Length `
        -ExpectedSha256 $Sha256 `
        -Description 'test artifact'
    Assert-ArtifactTest `
        -Condition ($Cached -ceq $Offline -and
            (Get-SwawHarnessFileSha256 -Path $Offline) -ceq $Sha256) `
        -Message 'valid cache was not reused without contacting its source'

    [IO.File]::WriteAllText($Cached, 'corrupt')
    [IO.File]::WriteAllText(
        $Source,
        'verified artifact bytes',
        [Text.UTF8Encoding]::new($false)
    )
    $Repaired = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source $Source `
        -ExpectedLength $Length `
        -ExpectedSha256 $Sha256 `
        -Description 'test artifact'
    Assert-ArtifactTest `
        -Condition ((Get-SwawHarnessFileSha256 -Path $Repaired) -ceq $Sha256) `
        -Message 'corrupt cache was not repaired from a verified source'
    $HashPinned = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source $Source `
        -ExpectedLength 0 `
        -ExpectedSha256 $Sha256 `
        -Description 'hash-pinned artifact' `
        -MaximumBytes 64MB
    Assert-ArtifactTest `
        -Condition ($HashPinned -ceq $Repaired) `
        -Message 'hash-pinned artifact required an unreliable declared length'

    $Orphan = Join-Path (Split-Path $Repaired -Parent) (
        '.artifact.bin.11111111111111111111111111111111.tmp'
    )
    [IO.File]::WriteAllText($Orphan, 'orphan')
    [void](Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source $Source `
        -ExpectedLength $Length `
        -ExpectedSha256 $Sha256 `
        -Description 'test artifact')
    Assert-ArtifactTest `
        -Condition (-not [IO.File]::Exists($Orphan)) `
        -Message 'orphaned download temporary file was not cleaned'

    $WrongHash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $WrongHashRejected = $false
    try {
        [void](Get-SwawHarnessVerifiedArtifact `
            -Context $Context `
            -Source $Source `
            -ExpectedLength $Length `
            -ExpectedSha256 $WrongHash `
            -Description 'wrong-hash artifact')
    } catch {
        $WrongHashRejected = $_.Exception.Message -like '*verification failed*'
    }
    $WrongRoot = Join-Path $Context.DownloadRoot (
        "sha256\aa\$WrongHash"
    )
    Assert-ArtifactTest `
        -Condition ($WrongHashRejected -and
            -not [IO.File]::Exists((Join-Path $WrongRoot 'artifact.bin'))) `
        -Message 'wrong-hash artifact passed or remained trusted in cache'

    $ExternalRoot = Join-Path $TestRoot 'external'
    [void][IO.Directory]::CreateDirectory($ExternalRoot)
    $Sentinel = Join-Path $ExternalRoot 'sentinel.txt'
    [IO.File]::WriteAllText($Sentinel, 'preserve')
    $ShaRoot = Join-Path $Context.DownloadRoot 'sha256'
    [void][IO.Directory]::CreateDirectory($ShaRoot)
    $JunctionPath = Join-Path $ShaRoot 'ff'
    [void](New-Item `
        -ItemType Junction `
        -Path $JunctionPath `
        -Target $ExternalRoot)
    $JunctionRejected = $false
    try {
        [void](Get-SwawHarnessVerifiedArtifact `
            -Context $Context `
            -Source $Source `
            -ExpectedLength $Length `
            -ExpectedSha256 ('f' * 64) `
            -Description 'junction artifact')
    } catch {
        $JunctionRejected = $_.Exception.Message -like '*reparse point*'
    }
    Assert-ArtifactTest `
        -Condition ($JunctionRejected -and [IO.File]::Exists($Sentinel)) `
        -Message 'artifact cache crossed a descendant junction'
    [IO.Directory]::Delete($JunctionPath)
    $JunctionPath = ''
} finally {
    if (-not [string]::IsNullOrWhiteSpace($JunctionPath) -and
        [IO.Directory]::Exists($JunctionPath)) {
        [IO.Directory]::Delete($JunctionPath)
    }
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap artifact cache' -ForegroundColor Green
