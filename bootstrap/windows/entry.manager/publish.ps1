[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [Parameter(Mandatory = $true)][string]$CandidatePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\context.ps1')
. (Join-Path $PSScriptRoot '..\builder\contract.ps1')
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot '..\builder\release\publication.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot '..\contract.json')
$Contract = Read-SwawHarnessWindowsEntryManagerContract `
    -Path (Join-Path $PSScriptRoot 'contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$BuildRoot = Join-Path $Context.BootstrapWindowsCacheRoot (
    "build\entry.manager\$($Contract.PlatformTargetId)"
)
$Candidate = Read-SwawHarnessBootstrapCandidate `
    -Path $CandidatePath `
    -Contract $Contract `
    -BuildRoot $BuildRoot
$Published = Publish-SwawHarnessRelease `
    -Context $Context `
    -Contract $Contract `
    -Candidate $Candidate `
    -ReleasesRoot $Context.EntryManagerReleaseRoot `
    -LockName 'publish-entry-manager-releases.lock'
Write-Host "[PUBLISHED] Entry Manager $($Published.ReleaseId)" `
    -ForegroundColor Green
Write-Output $Published
