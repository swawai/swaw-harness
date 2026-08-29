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
        [string[]]$UnsetEnvironmentVariables = @()
    )

    $EntryManagerRoot = $script:SwawHarnessWindowsEntryManagerRoot
    [void](Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot (Join-Path $EntryManagerRoot '..\..\..'))
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $EntryManagerRoot '..\contract.json')
    $Contract = Read-SwawHarnessWindowsEntryManagerContract `
        -Path (Join-Path $EntryManagerRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
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

    $BuildLock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "build-entry-manager-$($Contract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $Context.DataRepo `
        -TimeoutSeconds 1800
    try {
        $CargoTargetRoot = $BuildRoot
        Assert-SwawHarnessCargoBuildPathBudget `
            -TargetRoot $CargoTargetRoot `
            -Contract $Contract `
            -CargoPath $CargoPath `
            -ManifestPath $ManifestPath `
            -WorkingDirectory $EntryManagerRoot
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

        $ArtifactPath = Join-Path $CargoTargetRoot (
            "$($Contract.PlatformTargetId)\release\$($Contract.BuildBinary)"
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
            -ControlledRoot $Context.BuildRoot
        Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
        Write-Output $CandidatePath
    } finally {
        $BuildLock.Dispose()
    }
}
