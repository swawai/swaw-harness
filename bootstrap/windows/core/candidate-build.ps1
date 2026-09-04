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
        [string[]]$UnsetEnvironmentVariables = @(),
        [IO.FileStream]$CandidateLifecycleLock = $null
    )

    $CoreRoot = $script:SwawHarnessWindowsCoreRoot
    $RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot (Join-Path $CoreRoot '..\..\..')
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $CoreRoot '..\contract.json')
    $Contracts = @(Read-SwawHarnessWindowsCoreContracts `
        -Path (Join-Path $CoreRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
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

    $LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
        -Context $Context `
        -PlatformTargetId $Contracts[0].PlatformTargetId `
        -ExistingLock $CandidateLifecycleLock
    $BuildLock = $null
    try {
        $BuildLock = Enter-SwawHarnessFileLock `
            -Path (Join-Path $Context.LockRoot (
                "build-core-$($Contracts[0].PlatformTargetId).lock"
            )) `
            -ControlledRoot $Context.DataRepo `
            -TimeoutSeconds 1800
        $CargoTargetRoot = $BuildRoot
        foreach ($Contract in $Contracts) {
            Assert-SwawHarnessCargoBuildPathBudget `
                -TargetRoot $CargoTargetRoot `
                -Contract $Contract `
                -CargoPath $CargoPath `
                -ManifestPath $WorkspaceManifest `
                -WorkingDirectory (Join-Path $RepositoryRoot 'core')
        }
        $RustTargetConfiguration = (
            "target.$($Contracts[0].PlatformTargetId).rustflags=" +
            '["-C","target-feature=+crt-static",' +
            '"-C","link-arg=/Brepro"]'
        )
        $Arguments = [Collections.Generic.List[string]]::new()
        foreach ($Argument in @(
            '--config',
            $RustTargetConfiguration,
            'build',
            '--locked',
            '--release'
        )) {
            $Arguments.Add([string]$Argument)
        }
        foreach ($Contract in $Contracts) {
            $Arguments.Add('--package')
            $Arguments.Add([string]$Contract.ProductPackage)
        }
        foreach ($Argument in @(
            '--manifest-path',
            $WorkspaceManifest,
            '--target',
            $Contracts[0].PlatformTargetId,
            '--target-dir',
            $CargoTargetRoot
        )) {
            $Arguments.Add([string]$Argument)
        }
        $Result = Invoke-SwawHarnessCapturedProcess `
            -Executable $CargoPath `
            -Arguments $Arguments.ToArray() `
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

        $CandidateRoots = [Collections.Generic.List[string]]::new()
        foreach ($Contract in $Contracts) {
            $ArtifactPath = Join-Path $CargoTargetRoot (
                "$($Contract.PlatformTargetId)\release\" +
                $Contract.BuildBinary
            )
            [void](Assert-SwawHarnessRegularFile `
                -Path $ArtifactPath `
                -Description 'Built Windows Core artifact' `
                -MaximumBytes $Contract.MaximumBytes)
            $CandidateRoot = Publish-SwawHarnessBootstrapCandidate `
                -ArtifactPath $ArtifactPath `
                -Contract $Contract `
                -BuildRoot $BuildRoot `
                -ControlledRoot $Context.BuildRoot
            Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
            $CandidateRoots.Add([string]$CandidateRoot)
        }
        Write-Output $CandidateRoots.ToArray()
    } finally {
        if ($null -ne $BuildLock) {
            $BuildLock.Dispose()
        }
        Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
    }
}
