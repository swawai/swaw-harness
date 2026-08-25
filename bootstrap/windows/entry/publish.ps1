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
$Contract = Read-SwawHarnessWindowsEntryContract `
    -Path (Join-Path $PSScriptRoot 'contract.json') `
    -TargetId $PlatformContract.TargetId
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$BuildRoot = Join-Path $Context.BootstrapWindowsCacheRoot (
    "build\entry\$($Contract.TargetId)"
)
$Candidate = Read-SwawHarnessBootstrapCandidate `
    -Path $CandidatePath `
    -Contract $Contract `
    -BuildRoot $BuildRoot
$Published = Publish-SwawHarnessRelease `
    -Context $Context `
    -Contract $Contract `
    -Candidate $Candidate `
    -ReleasesRoot $Context.EntryReleaseRoot `
    -LockName 'publish-entry-releases.lock'
Write-Host "[PUBLISHED] Entry executable $($Published.ReleaseId)" `
    -ForegroundColor Green
Write-Output $Published
