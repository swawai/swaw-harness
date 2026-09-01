[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $WindowsRoot 'core\candidate-build.ps1')
. (Join-Path $WindowsRoot 'core\contract.ps1')
. (Join-Path $WindowsRoot 'core\module-publication.ps1')
. (Join-Path $WindowsRoot 'entry\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry.manager\candidate-build.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
    -Path (Join-Path $WindowsRoot 'core\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId)
$HelloworldContracts = @($CoreContracts | Where-Object {
    $_.ModuleId -ceq 'swaw/templates/helloworld'
})
$DevContracts = @($CoreContracts | Where-Object {
    $_.ModuleId -ceq 'swaw/core/dev'
})
if ($HelloworldContracts.Count -ne 1 -or $DevContracts.Count -ne 1) {
    throw 'Skill invocation test requires one Helloworld and one Dev contract.'
}
$HelloworldContract = $HelloworldContracts[0]
$DevContract = $DevContracts[0]

$SharedContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
$Toolchain = Get-SwawHarnessBootstrapToolchain `
    -Context $SharedContext `
    -Contract $PlatformContract
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $SharedContext `
    -Contract $PlatformContract `
    -Toolchain $Toolchain
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $Context = New-SwawHarnessWindowsBootstrapContext `
        -DataRepo (Join-Path $TestRoot 'data.repo')
    $CoreCandidateRoots = @(
        Invoke-SwawHarnessWindowsCoreCandidateBuild `
            -Context $Context `
            -CargoPath $Plan.CargoPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    $EntryCandidateRoot = Invoke-SwawHarnessWindowsEntryCandidateBuild `
        -Context $Context `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryManagerCandidateRoots = @(
        Invoke-SwawHarnessWindowsEntryManagerCandidateBuild `
            -Context $Context `
            -CargoPath $Plan.CargoPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    $Releases = @(Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidateRoots ([string[]]$CoreCandidateRoots) `
        -EntryCandidateRoot ([string]$EntryCandidateRoot) `
        -EntryManagerCandidateRoots ([string[]]$EntryManagerCandidateRoots))
    if ($Releases.Count -ne 1) {
        throw 'Skill invocation test requires one Bootstrap Release.'
    }

    $ModuleAdminRoot = Join-Path $TestRoot 'data\admin'
    [void][IO.Directory]::CreateDirectory($ModuleAdminRoot)
    Copy-Item `
        -LiteralPath (Join-Path $RepositoryRoot 'data\admin\map') `
        -Destination (Join-Path $ModuleAdminRoot 'map') `
        -Recurse
    $PublishedModules = @(Publish-SwawHarnessWindowsCoreModules `
        -Context $Context `
        -BootstrapRelease $Releases[0])
    if ($PublishedModules.Count -ne $CoreContracts.Count) {
        throw 'Skill invocation fixture must publish every Core Module Release.'
    }

    $TestEnvironment = [ordered]@{}
    foreach ($Entry in $Plan.EnvironmentVariables.GetEnumerator()) {
        $TestEnvironment[$Entry.Key] = $Entry.Value
    }
    $TestEnvironment['SWAW_HARNESS_TEST_DATA_HOME'] = `
        (Join-Path $TestRoot 'data')
    $TestEnvironment['SWAW_HARNESS_TEST_HELLOWORLD_VERSION'] = `
        [string]$HelloworldContract.ModuleVersion
    $TestEnvironment['SWAW_HARNESS_TEST_DEV_VERSION'] = `
        [string]$DevContract.ModuleVersion
    $TestEnvironment['SWAW_HARNESS_TEST_PLATFORM_TARGET_ID'] = `
        [string]$PlatformContract.PlatformTargetId
    $WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
    $CargoTargetRoot = Join-Path $TestRoot 'cargo-target'
    $RustTargetConfiguration = (
        "target.$($PlatformContract.PlatformTargetId).rustflags=" +
        '["-C","target-feature=+crt-static"]'
    )
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Plan.CargoPath `
        -Arguments @(
            '--config', $RustTargetConfiguration,
            'test',
            '--locked',
            '--manifest-path', $WorkspaceManifest,
            '--package', 'swaw-harness-core-protocol',
            '--lib',
            '--target', $PlatformContract.PlatformTargetId,
            '--target-dir', $CargoTargetRoot,
            'module_release::tests::isolated_installed_',
            '--',
            '--ignored'
        ) `
        -WorkingDirectory (Join-Path $RepositoryRoot 'core') `
        -EnvironmentVariables $TestEnvironment `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -TimeoutSeconds 1800
    if ($Result.ExitCode -ne 0) {
        throw (
            "Installed Skill invocation failed with exit code $($Result.ExitCode). " +
            "$($Result.Error) $($Result.Output)"
        ).Trim()
    }

    Write-Host '[PASS] isolated installed Skill invocation' `
        -ForegroundColor Green
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}
