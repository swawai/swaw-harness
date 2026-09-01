[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'core\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')

$DataRepo = Join-Path $RepositoryRoot 'data.repo'
$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
    -Path (Join-Path $WindowsRoot 'core\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId)
$DevContracts = @($CoreContracts | Where-Object {
    $_.ModuleId -ceq 'swaw/core/dev'
})
if ($DevContracts.Count -ne 1) {
    throw 'Skill invocation test requires exactly one Dev Module contract.'
}
$DevContract = $DevContracts[0]

$Releases = @(& (Join-Path $WindowsRoot 'main.ps1'))
if ($Releases.Count -ne 1) {
    throw 'Skill invocation test requires one Bootstrap Release.'
}

$Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
$DataHome = Join-Path (Split-Path -Path $DataRepo -Parent) 'data'
$ToolchainRoot = Get-SwawHarnessToolchainTargetPath `
    -Context $Context `
    -Contract $PlatformContract
$Toolchain = Get-SwawHarnessValidToolchain `
    -Context $Context `
    -Contract $PlatformContract `
    -InstallRoot $ToolchainRoot
if ($null -eq $Toolchain) {
    throw 'Skill invocation test requires the valid Bootstrap toolchain.'
}
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $Context `
    -Contract $PlatformContract `
    -Toolchain $Toolchain
$TestEnvironment = [ordered]@{}
foreach ($Entry in $Plan.EnvironmentVariables.GetEnumerator()) {
    $TestEnvironment[$Entry.Key] = $Entry.Value
}
$TestEnvironment['SWAW_HARNESS_TEST_DATA_HOME'] = $DataHome
$TestEnvironment['SWAW_HARNESS_TEST_MODULE_VERSION'] = `
    [string]$DevContract.ModuleVersion
$TestEnvironment['SWAW_HARNESS_TEST_PLATFORM_TARGET_ID'] = `
    [string]$DevContract.PlatformTargetId
$WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
$CargoTargetRoot = Join-Path $Context.BuildRoot 'skill-invocation-test'
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
        'module_release::tests::repository_installed_skill_runs_and_writes_export',
        '--',
        '--exact',
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

Write-Host '[PASS] installed Skill invocation' -ForegroundColor Green
