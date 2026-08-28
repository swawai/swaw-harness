[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [Parameter(Mandatory = $true)][string]$CargoPath,
    [Collections.IDictionary]$EnvironmentVariables = @{},
    [string[]]$UnsetEnvironmentVariables = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\context.ps1')
. (Join-Path $PSScriptRoot '..\builder\contract.ps1')
. (Join-Path $PSScriptRoot '..\builder\process.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$RepositoryRoot = Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot $RepositoryRoot

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot '..\contract.json')
$Contract = Read-SwawHarnessWindowsEntryManagerContract `
    -Path (Join-Path $PSScriptRoot 'contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$BootstrapWindowsCacheRoot = $Context.BootstrapWindowsCacheRoot
$BuildRoot = Join-Path $BootstrapWindowsCacheRoot (
    "build\entry.manager\$($Contract.PlatformTargetId)"
)
$BuildRoot = Assert-SwawHarnessPathInsideRoot `
    -Path $BuildRoot `
    -Root $BootstrapWindowsCacheRoot `
    -Activity 'building the Windows Entry Manager candidate'
[void][IO.Directory]::CreateDirectory($BuildRoot)
$NativeBuildRoot = Assert-SwawHarnessPathInsideRoot `
    -Path (Join-Path $Context.NativeBuildRoot 'm') `
    -Root $Context.NativeRoot `
    -Activity 'building the Windows Entry Manager candidate'
[void][IO.Directory]::CreateDirectory($NativeBuildRoot)

$CargoPath = Get-SwawHarnessFullPath -Path $CargoPath
[void](Assert-SwawHarnessRegularFile `
    -Path $CargoPath `
    -Description 'Cargo executable')
$ManifestPath = Join-Path $PSScriptRoot 'Cargo.toml'
$LockPath = Join-Path $PSScriptRoot 'Cargo.lock'
[void](Assert-SwawHarnessRegularFile `
    -Path $ManifestPath `
    -Description 'Entry Manager Cargo manifest' `
    -MaximumBytes 1MB)
[void](Assert-SwawHarnessRegularFile `
    -Path $LockPath `
    -Description 'Entry Manager Cargo lock' `
    -MaximumBytes 1MB)

$BuildLock = Enter-SwawHarnessFileLock `
    -Path (Join-Path $Context.LockRoot (
        "build-entry-manager-$($Contract.PlatformTargetId).lock"
    )) `
    -ControlledRoot $Context.BootstrapWindowsRoot `
    -TimeoutSeconds 1800
try {
    $CargoTargetRoot = $NativeBuildRoot
    Assert-SwawHarnessCargoBuildPathBudget `
        -TargetRoot $CargoTargetRoot `
        -Contract $Contract `
        -CargoPath $CargoPath `
        -ManifestPath $ManifestPath `
        -WorkingDirectory $PSScriptRoot
    $RustTargetConfiguration = (
        "target.$($Contract.PlatformTargetId).rustflags=" +
        '["-C","target-feature=+crt-static"]'
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
        $ManifestPath,
        '--target',
        $Contract.PlatformTargetId,
        '--target-dir',
        $CargoTargetRoot
    )
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $CargoPath `
        -Arguments $Arguments `
        -WorkingDirectory $PSScriptRoot `
        -EnvironmentVariables $EnvironmentVariables `
        -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
        -TimeoutSeconds 1800
    if ($Result.ExitCode -ne 0) {
        throw (
            "Entry Manager Cargo build failed with exit code " +
            "$($Result.ExitCode). $($Result.Error) $($Result.Output)"
        ).Trim()
    }
    [void](Assert-SwawHarnessNativeTreePathBudget `
        -Root $CargoTargetRoot `
        -Description 'Entry Manager Cargo output path')

    $ArtifactPath = Join-Path $CargoTargetRoot (
        "$($Contract.PlatformTargetId)\release\$($Contract.ProductBinary)"
    )
    $Artifact = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Built Windows Entry Manager' `
        -MaximumBytes $Contract.MaximumBytes
    if ([long]$Artifact.Length -le 0) {
        throw 'Built Windows Entry Manager is empty.'
    }
    $CandidatePath = Publish-SwawHarnessBootstrapCandidate `
        -ArtifactPath $ArtifactPath `
        -Contract $Contract `
        -BuildRoot $BuildRoot `
        -ControlledRoot $BootstrapWindowsCacheRoot
    Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
    Write-Output $CandidatePath
} finally {
    $BuildLock.Dispose()
}
