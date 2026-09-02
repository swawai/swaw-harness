Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\context.ps1')
. (Join-Path $PSScriptRoot 'builder\contract.ps1')
. (Join-Path $PSScriptRoot 'builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'builder\release\publication.ps1')
. (Join-Path $PSScriptRoot 'core\contract.ps1')
. (Join-Path $PSScriptRoot 'user\contract.ps1')
. (Join-Path $PSScriptRoot 'frontend\contract.ps1')

$script:SwawHarnessWindowsPublicationRoot = $PSScriptRoot

function Get-SwawHarnessWindowsProductContracts {
    param(
        [Parameter(Mandatory = $true)][string]$WindowsRoot,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    return @(
        Read-SwawHarnessWindowsCoreContracts `
            -Path (Join-Path $WindowsRoot 'core\contract.json') `
            -PlatformTargetId $PlatformTargetId
        Read-SwawHarnessWindowsUserCliContract `
            -Path (Join-Path $WindowsRoot 'user\contract.json') `
            -PlatformTargetId $PlatformTargetId
        Read-SwawHarnessWindowsFrontendContracts `
            -Path (Join-Path $WindowsRoot 'frontend\contract.json') `
            -PlatformTargetId $PlatformTargetId
    )
}

function Publish-SwawHarnessWindowsProducts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string[]]$CoreCandidateRoots,
        [Parameter(Mandatory = $true)][string]$UserCliCandidateRoot,
        [Parameter(Mandatory = $true)][string[]]$FrontendCandidateRoots,
        [IO.FileStream]$CandidateLifecycleLock = $null
    )

    $WindowsRoot = $script:SwawHarnessWindowsPublicationRoot
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Contracts = @(Get-SwawHarnessWindowsProductContracts `
        -WindowsRoot $WindowsRoot `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    $CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
        -Path (Join-Path $WindowsRoot 'core\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    if ($CoreCandidateRoots.Count -ne $CoreContracts.Count) {
        throw 'Windows publication requires every Core artifact Candidate.'
    }
    if ($FrontendCandidateRoots.Count -ne 2) {
        throw 'Windows publication requires both frontend candidates.'
    }
    $CandidateRoots = @(
        $CoreCandidateRoots
        $UserCliCandidateRoot
        $FrontendCandidateRoots[0]
        $FrontendCandidateRoots[1]
    )
    $ProductNames = @(
        @($CoreContracts | ForEach-Object { 'core' })
        'user'
        'frontend'
        'frontend'
    )
    $ConsumerLock = Enter-SwawHarnessCandidateConsumerLock `
        -Context $Context `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    try {
        $LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
            -Context $Context `
            -PlatformTargetId $PlatformContract.PlatformTargetId `
            -ExistingLock $CandidateLifecycleLock
        try {
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
        } finally {
            Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
        }
    } finally {
        $ConsumerLock.Dispose()
    }
}

function Clear-SwawHarnessWindowsProductCandidates {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [IO.FileStream]$CandidateLifecycleLock = $null
    )

    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $script:SwawHarnessWindowsPublicationRoot 'contract.json')
    $LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
        -Context $Context `
        -PlatformTargetId $PlatformContract.PlatformTargetId `
        -ExistingLock $CandidateLifecycleLock
    $CleanupLock = $null
    try {
        $CleanupLock = Enter-SwawHarnessCandidateCleanupLock `
            -Context $Context `
            -PlatformTargetId $PlatformContract.PlatformTargetId
        if ($null -eq $CleanupLock) {
            Write-Warning (
                'Published Windows Candidates are still in use; ' +
                'a later successful Bootstrap invocation will retry cleanup.'
            )
            return
        }
        $CandidateRoots = @('core', 'user', 'frontend') | ForEach-Object {
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
    } finally {
        if ($null -ne $CleanupLock) {
            $CleanupLock.Dispose()
        }
        Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
    }
}
