Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\context.ps1')
. (Join-Path $PSScriptRoot '..\builder\contract.ps1')
. (Join-Path $PSScriptRoot '..\builder\process.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$script:SwawHarnessWindowsCoreRoot = $PSScriptRoot

function Invoke-SwawHarnessWindowsCoreCandidateBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$CargoPath,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @()
    )

    $CoreRoot = $script:SwawHarnessWindowsCoreRoot
    $RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot (Join-Path $CoreRoot '..\..\..')
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $CoreRoot '..\contract.json')
    $Contract = Read-SwawHarnessWindowsCoreContract `
        -Path (Join-Path $CoreRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $BuildRoot = Join-Path $Context.BuildRoot 'core'
    $BuildRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $BuildRoot `
        -Root $Context.BuildRoot `
        -Activity 'building the Windows Core candidate'
    [void][IO.Directory]::CreateDirectory($BuildRoot)

    $CargoPath = Get-SwawHarnessFullPath -Path $CargoPath
    [void](Assert-SwawHarnessRegularFile `
        -Path $CargoPath `
        -Description 'Cargo executable')
    $WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
    [void](Assert-SwawHarnessRegularFile `
        -Path $WorkspaceManifest `
        -Description 'Rust workspace manifest' `
        -MaximumBytes 1048576)

    $BuildLock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "build-core-$($Contract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $Context.DataRepo `
        -TimeoutSeconds 1800
    try {
        $CargoTargetRoot = $BuildRoot
        Assert-SwawHarnessCargoBuildPathBudget `
            -TargetRoot $CargoTargetRoot `
            -Contract $Contract `
            -CargoPath $CargoPath `
            -ManifestPath $WorkspaceManifest `
            -WorkingDirectory (Join-Path $RepositoryRoot 'core')
        $RustTargetConfiguration = (
            "target.$($Contract.PlatformTargetId).rustflags=" +
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
            $Contract.ProductPackage,
            '--manifest-path',
            $WorkspaceManifest,
            '--target',
            $Contract.PlatformTargetId,
            '--target-dir',
            $CargoTargetRoot
        )
        $Result = Invoke-SwawHarnessCapturedProcess `
            -Executable $CargoPath `
            -Arguments $Arguments `
            -WorkingDirectory (Join-Path $RepositoryRoot 'core') `
            -EnvironmentVariables $EnvironmentVariables `
            -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
            -TimeoutSeconds 1800
        if ($Result.ExitCode -ne 0) {
            throw (
                "Core Cargo build failed with exit code $($Result.ExitCode). " +
                "$($Result.Error) $($Result.Output)"
            ).Trim()
        }
        [void](Assert-SwawHarnessNativeTreePathBudget `
            -Root $CargoTargetRoot `
            -Description 'Core Cargo output path')

        $ArtifactPath = Join-Path $CargoTargetRoot (
            "$($Contract.PlatformTargetId)\release\$($Contract.BuildBinary)"
        )
        [void](Assert-SwawHarnessRegularFile `
            -Path $ArtifactPath `
            -Description 'Built Windows Core' `
            -MaximumBytes $Contract.MaximumBytes)
        $CandidatePath = Publish-SwawHarnessBootstrapCandidate `
            -ArtifactPath $ArtifactPath `
            -Contract $Contract `
            -BuildRoot $BuildRoot `
            -ControlledRoot $Context.BuildRoot
        Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
        Write-Output $CandidatePath
    } finally {
        $BuildLock.Dispose()
    }
}
