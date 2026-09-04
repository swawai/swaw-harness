Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\context.ps1')
. (Join-Path $PSScriptRoot '..\builder\contract.ps1')
. (Join-Path $PSScriptRoot '..\builder\process.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$script:SwawHarnessWindowsCoreHostRoot = $PSScriptRoot

function Invoke-SwawHarnessWindowsCoreHostCandidateBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$CargoPath,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @(),
        [IO.FileStream]$CandidateLifecycleLock = $null
    )

    $HostRoot = $script:SwawHarnessWindowsCoreHostRoot
    $RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot (Join-Path $HostRoot '..\..\..')
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $HostRoot '..\contract.json')
    $Contract = Read-SwawHarnessWindowsCoreHostContract `
        -Path (Join-Path $HostRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $BuildRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.BuildRoot 'host') `
        -Root $Context.BuildRoot `
        -Activity 'building the Windows Core Host candidate'
    [void][IO.Directory]::CreateDirectory($BuildRoot)
    $CargoPath = Get-SwawHarnessFullPath -Path $CargoPath
    [void](Assert-SwawHarnessRegularFile `
        -Path $CargoPath `
        -Description 'Cargo executable')
    $WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
    [void](Assert-SwawHarnessRegularFile `
        -Path $WorkspaceManifest `
        -Description 'Core Rust workspace manifest' `
        -MaximumBytes 1MB)

    $LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
        -Context $Context `
        -PlatformTargetId $Contract.PlatformTargetId `
        -ExistingLock $CandidateLifecycleLock
    $BuildLock = $null
    try {
        $BuildLock = Enter-SwawHarnessFileLock `
            -Path (Join-Path $Context.LockRoot (
                "build-host-$($Contract.PlatformTargetId).lock"
            )) `
            -ControlledRoot $Context.DataRepo `
            -TimeoutSeconds 1800
        Assert-SwawHarnessCargoBuildPathBudget `
            -TargetRoot $BuildRoot `
            -Contract $Contract `
            -CargoPath $CargoPath `
            -ManifestPath $WorkspaceManifest `
            -WorkingDirectory (Join-Path $RepositoryRoot 'core')
        $RustTargetConfiguration = (
            "target.$($Contract.PlatformTargetId).rustflags=" +
            '["-C","target-feature=+crt-static",' +
            '"-C","link-arg=/Brepro"]'
        )
        $Result = Invoke-SwawHarnessCapturedProcess `
            -Executable $CargoPath `
            -Arguments @(
                '--config', $RustTargetConfiguration,
                'build', '--locked', '--release',
                '--package', $Contract.ProductPackage,
                '--manifest-path', $WorkspaceManifest,
                '--target', $Contract.PlatformTargetId,
                '--target-dir', $BuildRoot
            ) `
            -WorkingDirectory (Join-Path $RepositoryRoot 'core') `
            -EnvironmentVariables $EnvironmentVariables `
            -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
            -TimeoutSeconds 1800
        if ($Result.ExitCode -ne 0) {
            throw (
                'Core Host Cargo build failed with exit code ' +
                "$($Result.ExitCode). $($Result.Error) $($Result.Output)"
            ).Trim()
        }
        [void](Assert-SwawHarnessNativeTreePathBudget `
            -Root $BuildRoot `
            -Description 'Core Host Cargo output path')
        $ArtifactPath = Join-Path $BuildRoot (
            "$($Contract.PlatformTargetId)\release\$($Contract.BuildBinary)"
        )
        $Artifact = Assert-SwawHarnessRegularFile `
            -Path $ArtifactPath `
            -Description 'Built Windows Core Host artifact' `
            -MaximumBytes $Contract.MaximumBytes
        if ([long]$Artifact.Length -le 0) {
            throw 'Built Windows Core Host artifact is empty.'
        }
        $CandidateRoot = Publish-SwawHarnessBootstrapCandidate `
            -ArtifactPath $ArtifactPath `
            -Contract $Contract `
            -BuildRoot $BuildRoot `
            -ControlledRoot $Context.BuildRoot
        Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
        Write-Output $CandidateRoot
    } finally {
        if ($null -ne $BuildLock) {
            $BuildLock.Dispose()
        }
        Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
    }
}
