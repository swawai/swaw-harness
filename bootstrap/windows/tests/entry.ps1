[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-EntryTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Entry executable test failed: $Message"
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
. (Join-Path $WindowsRoot 'entry\contract.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRoot = Resolve-SwawHarnessWindowsTestDataRoot `
    -DataRoot $DataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRoot $DataRoot
try {
    $SharedContext = New-SwawHarnessWindowsBootstrapContext `
        -DataRoot $DataRoot
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
        throw 'Entry executable test requires the Contract toolchain to be installed.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain
    $CandidatePath = & (Join-Path $WindowsRoot 'entry\build.ps1') `
        -DataRoot $TestRoot `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryContract = Read-SwawHarnessWindowsEntryContract `
        -Path (Join-Path $WindowsRoot 'entry\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $TestContext = New-SwawHarnessWindowsBootstrapContext -DataRoot $TestRoot
    $BuildRoot = Join-Path $TestContext.BootstrapWindowsCacheRoot (
        "build\entry\$($PlatformContract.PlatformTargetId)"
    )
    $Candidate = Read-SwawHarnessBootstrapCandidate `
        -Path ([string]$CandidatePath) `
        -Contract $EntryContract `
        -BuildRoot $BuildRoot
    $Artifact = Get-Item -LiteralPath $Candidate.ArtifactPath
    Assert-EntryTest `
        -Condition (
            $Artifact.Name -ceq 'swaw-harness-entry.exe' -and
            $Artifact.Length -gt 0 -and
            $Artifact.Length -le $EntryContract.MaximumBytes
        ) `
        -Message 'Entry executable build did not produce a valid Candidate'
    [void](Assert-SwawHarnessNoExternalCrtImports `
        -ArtifactPath $Candidate.ArtifactPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)

    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Candidate.ArtifactPath `
        -Arguments @() `
        -WorkingDirectory (Split-Path $Candidate.ArtifactPath -Parent)
    Assert-EntryTest `
        -Condition (
            $Result.ExitCode -eq 1 -and
            $Result.Error -ceq (
                '[ERROR] Swaw Harness Entry executable runtime is not ' +
                'implemented yet; this artifact is for build and ' +
                'publication validation only.'
            )
        ) `
        -Message 'development Entry executable did not fail explicitly'

    $Implementation = [IO.File]::ReadAllText(
        (Join-Path $WindowsRoot 'entry\entry.c')
    )
    Assert-EntryTest `
        -Condition (
            $Implementation -notmatch (
                'SWAWKIT|PowerShell|core\.release|' +
                'data\.entry|bootstrap\\windows'
            )
        ) `
        -Message 'deferred runtime or legacy Bootstrap behavior leaked in'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Entry executable build' `
    -ForegroundColor Green
