Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\release\selector.ps1')
. (Join-Path $PSScriptRoot 'core\contract.ps1')
. (Join-Path $PSScriptRoot 'entry\contract.ps1')
. (Join-Path $PSScriptRoot 'entry.manager\contract.ps1')

$script:SwawHarnessWindowsPublicationRoot = $PSScriptRoot

function Publish-SwawHarnessWindowsProducts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [Parameter(Mandatory = $true)][string]$CoreCandidatePath,
        [Parameter(Mandatory = $true)][string]$EntryCandidatePath,
        [Parameter(Mandatory = $true)][string]$EntryManagerCandidatePath
    )

    $WindowsRoot = $script:SwawHarnessWindowsPublicationRoot
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
    $CoreContract = Read-SwawHarnessWindowsCoreContract `
        -Path (Join-Path $WindowsRoot 'core\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $EntryContract = Read-SwawHarnessWindowsEntryContract `
        -Path (Join-Path $WindowsRoot 'entry\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $EntryManagerContract = Read-SwawHarnessWindowsEntryManagerContract `
        -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId

    $PublicationLock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "publish-harness-$($PlatformContract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $Context.BootstrapWindowsRoot `
        -TimeoutSeconds 1800
    try {
        $CoreResults = @(& (Join-Path $WindowsRoot 'core\publish.ps1') `
            -DataRoot $Context.DataRoot `
            -CandidatePath $CoreCandidatePath)
        if ($CoreResults.Count -ne 1) {
            throw 'Core publish must return exactly one Release result.'
        }
        $EntryResults = @(& (Join-Path $WindowsRoot 'entry\publish.ps1') `
            -DataRoot $Context.DataRoot `
            -CandidatePath $EntryCandidatePath)
        if ($EntryResults.Count -ne 1) {
            throw 'Entry executable publish must return exactly one Release result.'
        }
        $EntryManagerResults = @(& (
            Join-Path $WindowsRoot 'entry.manager\publish.ps1'
        ) `
            -DataRoot $Context.DataRoot `
            -CandidatePath $EntryManagerCandidatePath)
        if ($EntryManagerResults.Count -ne 1) {
            throw 'Entry Manager publish must return exactly one Release result.'
        }
        $PublishedCore = $CoreResults[0]
        $PublishedEntry = $EntryResults[0]
        $PublishedEntryManager = $EntryManagerResults[0]

        $SelectedCore = Read-SwawHarnessSelectedRelease `
            -ReleasesRoot $Context.CoreReleaseRoot `
            -Contract $CoreContract
        $SelectedEntry = Read-SwawHarnessSelectedRelease `
            -ReleasesRoot $Context.EntryReleaseRoot `
            -Contract $EntryContract
        $SelectedEntryManager = Read-SwawHarnessSelectedRelease `
            -ReleasesRoot $Context.EntryManagerReleaseRoot `
            -Contract $EntryManagerContract
        if ([string]$SelectedCore.ReleaseId -cne
                [string]$PublishedCore.ReleaseId) {
            throw 'Published Core Release does not match its selected Release.'
        }
        if ([string]$SelectedEntry.ReleaseId -cne
                [string]$PublishedEntry.ReleaseId) {
            throw (
                'Published Entry executable Release does not match its ' +
                'selected Release.'
            )
        }
        if ([string]$SelectedEntryManager.ReleaseId -cne
                [string]$PublishedEntryManager.ReleaseId) {
            throw (
                'Published Entry Manager Release does not match its ' +
                'selected Release.'
            )
        }
        return [pscustomobject][ordered]@{
            CoreRelease = $SelectedCore
            EntryRelease = $SelectedEntry
            EntryManagerRelease = $SelectedEntryManager
        }
    } finally {
        $PublicationLock.Dispose()
    }
}
