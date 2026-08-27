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
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$ContractPath = Join-Path $PSScriptRoot '..\contract.json'
$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path $ContractPath
$Contract = Read-SwawHarnessWindowsCoreContract `
    -Path (Join-Path $PSScriptRoot 'contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$BootstrapWindowsRoot = $Context.BootstrapWindowsRoot
$BootstrapWindowsCacheRoot = $Context.BootstrapWindowsCacheRoot
$BuildRoot = Join-Path $BootstrapWindowsCacheRoot (
    "build\core\$($Contract.PlatformTargetId)"
)
$BuildRoot = Assert-SwawHarnessPathInsideRoot `
    -Path $BuildRoot `
    -Root $BootstrapWindowsCacheRoot `
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
    -ControlledRoot $BootstrapWindowsRoot `
    -TimeoutSeconds 1800
try {
    $CargoTargetRoot = Join-Path $BuildRoot 'cargo-target'
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

    $ArtifactPath = Join-Path $CargoTargetRoot (
        "$($Contract.PlatformTargetId)\release\$($Contract.ProductBinary)"
    )
    [void](Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'Built Windows Core' `
        -MaximumBytes $Contract.MaximumBytes)
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
