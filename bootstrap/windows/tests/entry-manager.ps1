[CmdletBinding()]
param([string]$DataRoot = '')

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
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $RepositoryRoot 'data'
}
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $WindowsRoot 'entry.manager\contract.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')

$TestRoot = Join-Path $RepositoryRoot (
    "data\_test\entry-manager-$([Guid]::NewGuid().ToString('N'))"
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
        throw 'Entry Manager test requires the Contract toolchain to be installed.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain
    $CandidatePath = & (Join-Path $WindowsRoot 'entry.manager\build.ps1') `
        -DataRoot $TestRoot `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $First = & (Join-Path $WindowsRoot 'entry.manager\publish.ps1') `
        -DataRoot $TestRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1
    $FirstCreated = (Get-Item -LiteralPath $First.ReleaseRoot).CreationTimeUtc
    $Second = & (Join-Path $WindowsRoot 'entry.manager\publish.ps1') `
        -DataRoot $TestRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1

    $EntryManagerContract = Read-SwawHarnessWindowsEntryManagerContract `
        -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
        -TargetId $PlatformContract.TargetId
    $Selected = Read-SwawHarnessSelectedRelease `
        -ReleasesRoot (Join-Path $TestRoot 'entry.manager.release') `
        -Contract $EntryManagerContract
    $Artifact = Get-Item -LiteralPath $Selected.ArtifactPath
    Assert-EntryManagerTest `
        -Condition (
            [string]$First.ReleaseId -ceq [string]$Second.ReleaseId -and
            [string]$Selected.ReleaseId -ceq [string]$First.ReleaseId -and
            $Artifact.Name -ceq 'swaw-harness-entry-manager.exe' -and
            $Artifact.Length -gt 0 -and
            $Artifact.Length -le $EntryManagerContract.MaximumBytes -and
            (Get-Item -LiteralPath $Second.ReleaseRoot).CreationTimeUtc -eq
                $FirstCreated
        ) `
        -Message 'Entry Manager publication is not immutable and idempotent'
    [void](Assert-SwawHarnessNoExternalCrtImports `
        -ArtifactPath $Selected.ArtifactPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)

    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Selected.ArtifactPath `
        -Arguments @() `
        -WorkingDirectory $Selected.Root
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

Write-Host '[PASS] Windows Entry Manager build and publication' `
    -ForegroundColor Green
