Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\context.ps1')
. (Join-Path $PSScriptRoot '..\builder\contract.ps1')
. (Join-Path $PSScriptRoot '..\builder\process.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$script:SwawHarnessWindowsEntryManagerRoot = $PSScriptRoot

function Invoke-SwawHarnessWindowsEntryManagerCandidateBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$CargoPath,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @(),
        [IO.FileStream]$CandidateLifecycleLock = $null
    )

    $EntryManagerRoot = $script:SwawHarnessWindowsEntryManagerRoot
    [void](Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot (Join-Path $EntryManagerRoot '..\..\..'))
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $EntryManagerRoot '..\contract.json')
    $Contracts = @(Read-SwawHarnessWindowsEntryManagerContracts `
        -Path (Join-Path $EntryManagerRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    $BuildRoot = Join-Path $Context.BuildRoot 'manager'
    $BuildRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $BuildRoot `
        -Root $Context.BuildRoot `
        -Activity 'building the Windows Entry Manager candidate'
    [void][IO.Directory]::CreateDirectory($BuildRoot)

    $CargoPath = Get-SwawHarnessFullPath -Path $CargoPath
    [void](Assert-SwawHarnessRegularFile `
        -Path $CargoPath `
        -Description 'Cargo executable')
    $ManifestPath = Join-Path $EntryManagerRoot 'Cargo.toml'
    $LockPath = Join-Path $EntryManagerRoot 'Cargo.lock'
    [void](Assert-SwawHarnessRegularFile `
        -Path $ManifestPath `
        -Description 'Entry Manager Cargo manifest' `
        -MaximumBytes 1MB)
    [void](Assert-SwawHarnessRegularFile `
        -Path $LockPath `
        -Description 'Entry Manager Cargo lock' `
        -MaximumBytes 1MB)

    $LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
        -Context $Context `
        -PlatformTargetId $Contracts[0].PlatformTargetId `
        -ExistingLock $CandidateLifecycleLock
    $BuildLock = $null
    try {
        $BuildLock = Enter-SwawHarnessFileLock `
            -Path (Join-Path $Context.LockRoot (
                "build-entry-manager-$($Contracts[0].PlatformTargetId).lock"
            )) `
            -ControlledRoot $Context.DataRepo `
            -TimeoutSeconds 1800
        $CargoTargetRoot = $BuildRoot
        Assert-SwawHarnessCargoBuildPathBudget `
            -TargetRoot $CargoTargetRoot `
            -Contract $Contracts[0] `
            -CargoPath $CargoPath `
            -ManifestPath $ManifestPath `
            -WorkingDirectory $EntryManagerRoot
        $RustTargetConfiguration = (
            "target.$($Contracts[0].PlatformTargetId).rustflags=" +
            '["-C","target-feature=+crt-static",' +
            '"-C","link-arg=/Brepro"]'
        )
        $Arguments = @(
            '--config',
            $RustTargetConfiguration,
            'build',
            '--locked',
            '--release',
            '--package',
            $Contracts[0].ProductPackage,
            '--manifest-path',
            $ManifestPath,
            '--target',
            $Contracts[0].PlatformTargetId,
            '--target-dir',
            $CargoTargetRoot
        )
        $Result = Invoke-SwawHarnessCapturedProcess `
            -Executable $CargoPath `
            -Arguments $Arguments `
            -WorkingDirectory $EntryManagerRoot `
            -EnvironmentVariables $EnvironmentVariables `
            -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
            -TimeoutSeconds 1800
        if ($Result.ExitCode -ne 0) {
            throw (
                'Entry Manager Cargo build failed with exit code ' +
                "$($Result.ExitCode). $($Result.Error) $($Result.Output)"
            ).Trim()
        }
        [void](Assert-SwawHarnessNativeTreePathBudget `
            -Root $CargoTargetRoot `
            -Description 'Entry Manager Cargo output path')

        foreach ($Contract in $Contracts) {
            $ArtifactPath = Join-Path $CargoTargetRoot (
                "$($Contract.PlatformTargetId)\release\$($Contract.BuildBinary)"
            )
            $Artifact = Assert-SwawHarnessRegularFile `
                -Path $ArtifactPath `
                -Description "Built Windows Entry Manager $($Contract.Role)" `
                -MaximumBytes $Contract.MaximumBytes
            if ([long]$Artifact.Length -le 0) {
                throw "Built Windows Entry Manager $($Contract.Role) is empty."
            }
            $CandidateRoot = Publish-SwawHarnessBootstrapCandidate `
                -ArtifactPath $ArtifactPath `
                -Contract $Contract `
                -BuildRoot $BuildRoot `
                -ControlledRoot $Context.BuildRoot
            Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
            Write-Output $CandidateRoot
        }
    } finally {
        if ($null -ne $BuildLock) {
            $BuildLock.Dispose()
        }
        Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
    }
}
