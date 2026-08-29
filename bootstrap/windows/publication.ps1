Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'builder\release\publication.ps1')
. (Join-Path $PSScriptRoot 'core\contract.ps1')
. (Join-Path $PSScriptRoot 'entry\contract.ps1')
. (Join-Path $PSScriptRoot 'entry.manager\contract.ps1')

$script:SwawHarnessWindowsPublicationRoot = $PSScriptRoot

function Get-SwawHarnessWindowsProductContracts {
    param(
        [Parameter(Mandatory = $true)][string]$WindowsRoot,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    return @(
        Read-SwawHarnessWindowsCoreContract `
            -Path (Join-Path $WindowsRoot 'core\contract.json') `
            -PlatformTargetId $PlatformTargetId
        Read-SwawHarnessWindowsEntryContract `
            -Path (Join-Path $WindowsRoot 'entry\contract.json') `
            -PlatformTargetId $PlatformTargetId
        Read-SwawHarnessWindowsEntryManagerContracts `
            -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
            -PlatformTargetId $PlatformTargetId
    )
}

function Publish-SwawHarnessWindowsProducts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$CoreCandidateRoot,
        [Parameter(Mandatory = $true)][string]$EntryCandidateRoot,
        [Parameter(Mandatory = $true)][string[]]$EntryManagerCandidateRoots
    )

    $WindowsRoot = $script:SwawHarnessWindowsPublicationRoot
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Contracts = @(Get-SwawHarnessWindowsProductContracts `
        -WindowsRoot $WindowsRoot `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    if ($EntryManagerCandidateRoots.Count -ne 2) {
        throw 'Windows publication requires both Entry Manager candidates.'
    }
    $CandidateRoots = @(
        $CoreCandidateRoot,
        $EntryCandidateRoot,
        $EntryManagerCandidateRoots[0],
        $EntryManagerCandidateRoots[1]
    )
    $ProductNames = @('core', 'entry', 'manager', 'manager')
    $Candidates = [Collections.Generic.List[object]]::new()
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $BuildRoot = Join-Path $Context.BuildRoot $ProductNames[$Index]
        $Candidates.Add((Read-SwawHarnessBootstrapCandidate `
            -CandidateRoot $CandidateRoots[$Index] `
            -Contract $Contracts[$Index] `
            -BuildRoot $BuildRoot))
    }
    return Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates.ToArray()
}

function Clear-SwawHarnessWindowsProductCandidates {
    param([Parameter(Mandatory = $true)]$Context)

    $CandidateRoots = @('core', 'entry', 'manager') | ForEach-Object {
        $BuildRoot = Assert-SwawHarnessPathInsideRoot `
            -Path (Join-Path $Context.BuildRoot $_) `
            -Root $Context.BuildRoot `
            -Activity 'planning Windows Candidate cleanup'
        Assert-SwawHarnessPathInsideRoot `
            -Path (Join-Path $BuildRoot 'candidates') `
            -Root $BuildRoot `
            -Activity 'planning Windows Candidate cleanup'
    }
    Remove-SwawHarnessControlledResidues `
        -ControlledRoot $Context.BuildRoot `
        -Paths $CandidateRoots `
        -Activity 'cleaning published Windows Candidates'
}
