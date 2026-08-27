[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-CoreReleaseTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Core Release test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = Join-Path $RepositoryRoot 'data'
}
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'core\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')
$TestRoot = Join-Path $RepositoryRoot (
    "data\_test\release-$([Guid]::NewGuid().ToString('N'))"
)
try {
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $CoreContract = Read-SwawHarnessWindowsCoreContract `
        -Path (Join-Path $WindowsRoot 'core\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $Context `
        -Contract $PlatformContract
    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $Context `
        -Contract $PlatformContract `
        -InstallRoot $InstallRoot
    if ($null -eq $Toolchain) {
        throw 'Core Release test requires the Contract toolchain to be installed.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $Context `
        -Contract $PlatformContract `
        -Toolchain $Toolchain
    $CandidatePath = & (Join-Path $WindowsRoot 'core\build.ps1') `
        -DataRoot $TestRoot `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $First = & (Join-Path $WindowsRoot 'core\publish.ps1') `
        -DataRoot $TestRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1
    $Second = & (Join-Path $WindowsRoot 'core\publish.ps1') `
        -DataRoot $TestRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1

    Assert-CoreReleaseTest `
        -Condition ([string]$First.ReleaseId -ceq [string]$Second.ReleaseId) `
        -Message 'idempotent publication changed the Release ID'
    $ReleaseDirectories = @(
        Get-ChildItem -LiteralPath (Join-Path $TestRoot 'core.release') `
            -Directory `
            -Force
    )
    Assert-CoreReleaseTest `
        -Condition ($ReleaseDirectories.Count -eq 1) `
        -Message 'idempotent publication created duplicate Releases'
    $Selector = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-CoreReleaseTest `
        -Condition ($Selector -ceq [string]$First.ReleaseId) `
        -Message 'target selector does not reference the published Release'

    $Executable = Join-Path `
        ([string]$First.ReleaseRoot) `
        $CoreContract.ProductBinary
    [void](Assert-SwawHarnessNoExternalCrtImports `
        -ArtifactPath $Executable `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
    $Output = & $Executable 'Bootstrap'
    Assert-CoreReleaseTest `
        -Condition (
            $LASTEXITCODE -eq 0 -and
            [string]$Output -ceq 'Hello, Bootstrap!'
        ) `
        -Message 'the published executable did not run correctly'

    $Candidate = Get-Content -Raw -LiteralPath $CandidatePath |
        ConvertFrom-Json
    $Candidate.artifact.length = [long]$Candidate.artifact.length + 1
    [IO.File]::WriteAllText(
        $CandidatePath,
        (($Candidate | ConvertTo-Json -Depth 8) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
    $Rejected = $false
    try {
        & (Join-Path $WindowsRoot 'core\publish.ps1') `
            -DataRoot $TestRoot `
            -CandidatePath ([string]$CandidatePath) | Out-Null
    } catch {
        $Rejected = $true
    }
    Assert-CoreReleaseTest `
        -Condition $Rejected `
        -Message 'publication accepted a tampered candidate descriptor'
    $SelectorAfterFailure = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-CoreReleaseTest `
        -Condition ($SelectorAfterFailure -ceq [string]$First.ReleaseId) `
        -Message 'failed publication changed the previous selector'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Core Release' -ForegroundColor Green
