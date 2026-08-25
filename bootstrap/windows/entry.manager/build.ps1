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

$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $PSScriptRoot '..\contract.json')
$Contract = Read-SwawHarnessWindowsEntryManagerContract `
    -Path (Join-Path $PSScriptRoot 'contract.json') `
    -TargetId $PlatformContract.TargetId
$Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
$BootstrapWindowsCacheRoot = $Context.BootstrapWindowsCacheRoot
$BuildRoot = Join-Path $BootstrapWindowsCacheRoot (
    "build\entry.manager\$($Contract.TargetId)"
)
$BuildRoot = Assert-SwawHarnessPathInsideRoot `
    -Path $BuildRoot `
    -Root $BootstrapWindowsCacheRoot `
    -Activity 'building the Windows Entry Manager candidate'
[void][IO.Directory]::CreateDirectory($BuildRoot)

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
        "build-entry-manager-$($Contract.TargetId).lock"
    )) `
    -ControlledRoot $Context.BootstrapWindowsRoot `
    -TimeoutSeconds 1800
try {
    $CargoTargetRoot = Join-Path $BuildRoot 'cargo-target'
    $RustTargetConfiguration = (
        "target.$($Contract.TargetId).rustflags=" +
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
        $Contract.TargetId,
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

    $ArtifactPath = Join-Path $CargoTargetRoot (
        "$($Contract.TargetId)\release\$($Contract.ProductBinary)"
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
