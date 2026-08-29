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

function Get-PeSubsystem {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Stream = [IO.File]::OpenRead($Path)
    $Reader = [IO.BinaryReader]::new($Stream)
    try {
        $Stream.Position = 0x3c
        $PeOffset = $Reader.ReadInt32()
        $Stream.Position = $PeOffset
        if ($Reader.ReadUInt32() -ne 0x00004550) {
            throw "PE signature is invalid: $Path"
        }
        $Stream.Position = $PeOffset + 24 + 68
        return $Reader.ReadUInt16()
    } finally {
        $Reader.Dispose()
        $Stream.Dispose()
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
    $CandidatePaths = @(Invoke-SwawHarnessWindowsEntryManagerCandidateBuild `
        -Context $TestContext `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
    $EntryManagerContracts = @(Read-SwawHarnessWindowsEntryManagerContracts `
        -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    $BuildRoot = Join-Path $TestContext.BuildRoot 'manager'
    Assert-EntryManagerTest `
        -Condition (
            $CandidatePaths.Count -eq 2 -and
            $EntryManagerContracts.Count -eq 2
        ) `
        -Message 'Entry Manager build did not produce both Candidates'
    $Candidates = @()
    for ($Index = 0; $Index -lt $EntryManagerContracts.Count; $Index++) {
        $Contract = $EntryManagerContracts[$Index]
        $Candidate = Read-SwawHarnessBootstrapCandidate `
            -Path ([string]$CandidatePaths[$Index]) `
            -Contract $Contract `
            -BuildRoot $BuildRoot
        $Artifact = Get-Item -LiteralPath $Candidate.ArtifactPath
        Assert-EntryManagerTest `
            -Condition (
                $Artifact.Name -ceq $Contract.ProductBinary -and
                $Artifact.Length -gt 0 -and
                $Artifact.Length -le $Contract.MaximumBytes
            ) `
            -Message "Entry Manager $($Contract.Role) Candidate is invalid"
        [void](Assert-SwawHarnessNoExternalCrtImports `
            -ArtifactPath $Candidate.ArtifactPath `
            -LinkerPath $Plan.LinkerPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
        $Candidates += $Candidate
    }
    Assert-EntryManagerTest `
        -Condition (
            (Get-PeSubsystem -Path $Candidates[0].ArtifactPath) -eq 3 -and
            (Get-PeSubsystem -Path $Candidates[1].ArtifactPath) -eq 2
        ) `
        -Message 'Entry Manager CLI and GUI PE subsystems are invalid'

    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Candidates[0].ArtifactPath `
        -Arguments @() `
        -WorkingDirectory (Split-Path $Candidates[0].ArtifactPath -Parent)
    Assert-EntryManagerTest `
        -Condition (
            $Result.ExitCode -eq 1 -and
            [string]::IsNullOrEmpty($Result.Output) -and
            $Result.Error -cmatch '^\[ERROR\] ' -and
            $Result.Error -match 'Entry operations are not implemented' -and
            $Result.Error -match 'console interface and release'
        ) `
        -Message (
            'Entry Manager CLI placeholder did not report its unimplemented ' +
            'operations and fail explicitly'
        )
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Entry Manager tests and build' `
    -ForegroundColor Green
