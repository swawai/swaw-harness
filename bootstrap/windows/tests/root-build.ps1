[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-RootBuildTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Root build test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'core\contract.ps1')
. (Join-Path $WindowsRoot 'entry\contract.ps1')
. (Join-Path $WindowsRoot 'entry.manager\contract.ps1')

& (Join-Path $RepositoryRoot 'build.cmd')
Assert-RootBuildTest `
    -Condition ($LASTEXITCODE -eq 0) `
    -Message "build.cmd exited with $LASTEXITCODE"

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$CoreContract = Read-SwawHarnessWindowsCoreContract `
    -Path (Join-Path $WindowsRoot 'core\contract.json') `
    -TargetId $PlatformContract.TargetId
$CoreReleasesRoot = Join-Path $RepositoryRoot 'data\core.release'
$CoreRelease = Read-SwawHarnessSelectedRelease `
    -ReleasesRoot $CoreReleasesRoot `
    -Contract $CoreContract
$EntryContract = Read-SwawHarnessWindowsEntryContract `
    -Path (Join-Path $WindowsRoot 'entry\contract.json') `
    -TargetId $PlatformContract.TargetId
$EntryReleasesRoot = Join-Path $RepositoryRoot 'data\entry.release'
$EntryRelease = Read-SwawHarnessSelectedRelease `
    -ReleasesRoot $EntryReleasesRoot `
    -Contract $EntryContract
$EntryManagerContract = Read-SwawHarnessWindowsEntryManagerContract `
    -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
    -TargetId $PlatformContract.TargetId
$EntryManagerReleasesRoot = Join-Path $RepositoryRoot 'data\entry.manager.release'
$EntryManagerRelease = Read-SwawHarnessSelectedRelease `
    -ReleasesRoot $EntryManagerReleasesRoot `
    -Contract $EntryManagerContract
Assert-RootBuildTest `
    -Condition (
        [IO.File]::Exists($CoreRelease.ArtifactPath) -and
        $CoreRelease.Root.StartsWith(
            $CoreReleasesRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [IO.File]::Exists($EntryRelease.ArtifactPath) -and
        $EntryRelease.Root.StartsWith(
            $EntryReleasesRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [IO.File]::Exists($EntryManagerRelease.ArtifactPath) -and
        $EntryManagerRelease.Root.StartsWith(
            $EntryManagerReleasesRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        -not [IO.File]::Exists(
            (Join-Path $RepositoryRoot 'swaw-harness-entry.exe')
        )
    ) `
    -Message 'build.cmd did not limit itself to three-product publication'

Write-Host '[PASS] repository root build.cmd' -ForegroundColor Green
