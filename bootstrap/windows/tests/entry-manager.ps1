[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-EntryManagerTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Entry Manager test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'builder\build\candidate.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $WindowsRoot 'entry.manager\contract.ps1')
. (Join-Path $WindowsRoot 'entry.manager\candidate-build.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $SharedContext = New-SwawHarnessWindowsBootstrapContext `
        -DataRepo $DataRepo
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $SharedContext `
        -Contract $PlatformContract
    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -InstallRoot $InstallRoot
    if ($null -eq $Toolchain) {
        throw 'Entry Manager test requires the Contract toolchain to be installed.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain
    $ManifestPath = Join-Path $WindowsRoot 'entry.manager\Cargo.toml'
    $CargoTestTargetRoot = Join-Path $TestRoot 'cargo-test-target'
    $RustTargetConfiguration = (
        "target.$($PlatformContract.PlatformTargetId).rustflags=" +
        '["-C","target-feature=+crt-static"]'
    )
    $TestResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $Plan.CargoPath `
        -Arguments @(
            '--config', $RustTargetConfiguration,
            'test',
            '--locked',
            '--manifest-path', $ManifestPath,
            '--target', $PlatformContract.PlatformTargetId,
            '--target-dir', $CargoTestTargetRoot
        ) `
        -WorkingDirectory (Join-Path $WindowsRoot 'entry.manager') `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -TimeoutSeconds 1800
    if ($TestResult.ExitCode -ne 0) {
        throw (
            "Entry Manager Cargo tests failed with exit code " +
            "$($TestResult.ExitCode). $($TestResult.Error) " +
            $TestResult.Output
        ).Trim()
    }
    $TestContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot
    $CandidatePath = Invoke-SwawHarnessWindowsEntryManagerCandidateBuild `
        -Context $TestContext `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryManagerContract = Read-SwawHarnessWindowsEntryManagerContract `
        -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $BuildRoot = Join-Path $TestContext.BuildRoot 'manager'
    $Candidate = Read-SwawHarnessBootstrapCandidate `
        -Path ([string]$CandidatePath) `
        -Contract $EntryManagerContract `
        -BuildRoot $BuildRoot
    $Artifact = Get-Item -LiteralPath $Candidate.ArtifactPath
    Assert-EntryManagerTest `
        -Condition (
            $Artifact.Name -ceq 'swaw-harness-entry-manager.exe' -and
            $Artifact.Length -gt 0 -and
            $Artifact.Length -le $EntryManagerContract.MaximumBytes
        ) `
        -Message 'Entry Manager build did not produce a valid Candidate'
    [void](Assert-SwawHarnessNoExternalCrtImports `
        -ArtifactPath $Candidate.ArtifactPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)

    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Candidate.ArtifactPath `
        -Arguments @() `
        -WorkingDirectory (Split-Path $Candidate.ArtifactPath -Parent)
    Assert-EntryManagerTest `
        -Condition (
            $Result.ExitCode -eq 1 -and
            [string]::IsNullOrEmpty($Result.Output) -and
            $Result.Error -cmatch '^\[ERROR\] ' -and
            $Result.Error -match 'control panel is not implemented' -and
            $Result.Error -match 'independent build and release'
        ) `
        -Message (
            'Entry Manager placeholder did not report its unimplemented ' +
            'control panel and fail explicitly'
        )
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Entry Manager tests and build' `
    -ForegroundColor Green
