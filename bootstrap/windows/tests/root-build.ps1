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
. (Join-Path $WindowsRoot 'publication.ps1')

& (Join-Path $RepositoryRoot 'build.cmd')
Assert-RootBuildTest `
    -Condition ($LASTEXITCODE -eq 0) `
    -Message "build.cmd exited with $LASTEXITCODE"

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$Contracts = @(Get-SwawHarnessWindowsProductContracts `
    -WindowsRoot $WindowsRoot `
    -PlatformTargetId $PlatformContract.PlatformTargetId)
$ReleasesRoot = Join-Path $RepositoryRoot 'data.repo\windows.release'
$Release = Read-SwawHarnessSelectedRelease `
    -ReleasesRoot $ReleasesRoot `
    -Contracts $Contracts
$ExpectedNames = @($Contracts | ForEach-Object { $_.ProductBinary })
$ActualNames = @($Release.Artifacts | ForEach-Object { $_.Name })
$CandidateMembers = @(
    foreach ($Product in @('core', 'entry', 'manager')) {
        $CandidatesRoot = Join-Path `
            $RepositoryRoot `
            "data.repo\windows.build\$Product\candidates"
        if ([IO.Directory]::Exists($CandidatesRoot)) {
            Get-ChildItem -LiteralPath $CandidatesRoot -Force
        }
    }
)
Assert-RootBuildTest `
    -Condition (
        $Release.Root.StartsWith(
            $ReleasesRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $Release.Artifacts.Count -eq $Contracts.Count -and
        [string]::Join('|', $ActualNames) -ceq
            [string]::Join('|', $ExpectedNames) -and
        @($Release.Artifacts | Where-Object {
            [IO.File]::Exists([string]$_.Path)
        }).Count -eq $Contracts.Count -and
        -not [IO.File]::Exists(
            (Join-Path $RepositoryRoot 'helloworld.exe')
        ) -and
        -not [IO.File]::Exists(
            (Join-Path $RepositoryRoot 'swaw-harness-dev.exe')
        ) -and
        -not [IO.File]::Exists(
            (Join-Path $RepositoryRoot 'entry.exe')
        ) -and
        -not [IO.File]::Exists(
            (Join-Path $RepositoryRoot 'swaw-harness.exe')
        ) -and
        -not [IO.File]::Exists(
            (Join-Path $RepositoryRoot 'swaw-harness-cli.exe')
        ) -and
        $CandidateMembers.Count -eq 0
    ) `
    -Message 'build.cmd did not limit itself to one bundle publication'

Write-Host '[PASS] repository root build.cmd' -ForegroundColor Green
