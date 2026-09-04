[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-UserCliTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "User CLI executable test failed: $Message"
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
. (Join-Path $WindowsRoot 'user\contract.ps1')
. (Join-Path $WindowsRoot 'user\candidate-build.ps1')
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
        throw 'User CLI executable test requires the Contract toolchain to be installed.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain
    $TestContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot
    $CandidateRoot = Invoke-SwawHarnessWindowsUserCliCandidateBuild `
        -Context $TestContext `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $UserCliContract = Read-SwawHarnessWindowsUserCliContract `
        -Path (Join-Path $WindowsRoot 'user\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $BuildRoot = Join-Path $TestContext.BuildRoot 'user'
    $Candidate = Read-SwawHarnessBootstrapCandidate `
        -CandidateRoot ([string]$CandidateRoot) `
        -Contract $UserCliContract `
        -BuildRoot $BuildRoot
    $Artifact = Get-Item -LiteralPath $Candidate.ArtifactPath
    Assert-UserCliTest `
        -Condition (
            $Artifact.Name -ceq 'user.exe' -and
            $Artifact.Length -gt 0 -and
            $Artifact.Length -le $UserCliContract.MaximumBytes
        ) `
        -Message 'User CLI executable build did not produce a valid Candidate'
    [void](Assert-SwawHarnessNoExternalCrtImports `
        -ArtifactPath $Candidate.ArtifactPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)

    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Candidate.ArtifactPath `
        -Arguments @() `
        -WorkingDirectory (Split-Path $Candidate.ArtifactPath -Parent)
    Assert-UserCliTest `
        -Condition (
            $Result.ExitCode -eq 1 -and
            $Result.Error -ceq
                '[ERROR] User CLI executable is not installed in DataHome.'
        ) `
        -Message 'uninstalled User CLI executable did not fail explicitly'

    $Implementation = @($UserCliContract.Sources | ForEach-Object {
        [IO.File]::ReadAllText((Join-Path $WindowsRoot "user\$_"))
    }) -join "`n"
    Assert-UserCliTest `
        -Condition (
            $Implementation -notmatch (
                'SWAWKIT|PowerShell|core\.release|' +
                'bootstrap\\windows'
            )
        ) `
        -Message 'deferred runtime or legacy Bootstrap behavior leaked in'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows User CLI executable build' `
    -ForegroundColor Green
