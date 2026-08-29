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
        [Parameter(Mandatory = $true)][string]$CoreCandidatePath,
        [Parameter(Mandatory = $true)][string]$EntryCandidatePath,
        [Parameter(Mandatory = $true)][string[]]$EntryManagerCandidatePaths
    )

    $WindowsRoot = $script:SwawHarnessWindowsPublicationRoot
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Contracts = @(Get-SwawHarnessWindowsProductContracts `
        -WindowsRoot $WindowsRoot `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    if ($EntryManagerCandidatePaths.Count -ne 2) {
        throw 'Windows publication requires both Entry Manager candidates.'
    }
    $CandidatePaths = @(
        $CoreCandidatePath,
        $EntryCandidatePath,
        $EntryManagerCandidatePaths[0],
        $EntryManagerCandidatePaths[1]
    )
    $ProductNames = @('core', 'entry', 'manager', 'manager')
    $Candidates = [Collections.Generic.List[object]]::new()
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $BuildRoot = Join-Path $Context.BuildRoot $ProductNames[$Index]
        $Candidates.Add((Read-SwawHarnessBootstrapCandidate `
            -Path $CandidatePaths[$Index] `
            -Contract $Contracts[$Index] `
            -BuildRoot $BuildRoot))
    }
    return Publish-SwawHarnessBootstrapRelease `
        -Context $Context `
        -Contracts $Contracts `
        -Candidates $Candidates.ToArray()
}
