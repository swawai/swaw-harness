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
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $RepositoryRoot 'data'
}
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $WindowsRoot 'entry\contract.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')

$TestRoot = Join-Path $RepositoryRoot (
    "data\_test\entry-$([Guid]::NewGuid().ToString('N'))"
)
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
    $First = & (Join-Path $WindowsRoot 'entry\publish.ps1') `
        -DataRoot $TestRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1
    $FirstCreated = (Get-Item -LiteralPath $First.ReleaseRoot).CreationTimeUtc
    $Second = & (Join-Path $WindowsRoot 'entry\publish.ps1') `
        -DataRoot $TestRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1

    $EntryContract = Read-SwawHarnessWindowsEntryContract `
        -Path (Join-Path $WindowsRoot 'entry\contract.json') `
        -TargetId $PlatformContract.TargetId
    $Selected = Read-SwawHarnessSelectedRelease `
        -ReleasesRoot (Join-Path $TestRoot 'entry.release') `
        -Contract $EntryContract
    $Artifact = Get-Item -LiteralPath $Selected.ArtifactPath
    Assert-EntryTest `
        -Condition (
            [string]$First.ReleaseId -ceq [string]$Second.ReleaseId -and
            [string]$Selected.ReleaseId -ceq [string]$First.ReleaseId -and
            $Artifact.Name -ceq 'swaw-harness-entry.exe' -and
            $Artifact.Length -gt 0 -and
            $Artifact.Length -le $EntryContract.MaximumBytes -and
            (Get-Item -LiteralPath $Second.ReleaseRoot).CreationTimeUtc -eq
                $FirstCreated
        ) `
        -Message 'Entry executable publication is not immutable and idempotent'
    [void](Assert-SwawHarnessNoExternalCrtImports `
        -ArtifactPath $Selected.ArtifactPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)

    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Selected.ArtifactPath `
        -Arguments @() `
        -WorkingDirectory $Selected.Root
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

Write-Host '[PASS] Windows Entry executable build and publication' `
    -ForegroundColor Green
