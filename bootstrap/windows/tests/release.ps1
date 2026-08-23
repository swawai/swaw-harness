[CmdletBinding()]
param([string]$VarRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ReleaseTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw "Release test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($VarRoot)) {
    $VarRoot = $RepositoryRoot
}
. (Join-Path $WindowsRoot '_lib\context.ps1')
. (Join-Path $WindowsRoot '_lib\contract.ps1')
. (Join-Path $WindowsRoot '_lib\toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot '_lib\toolchain\environment.ps1')
$TestRoot = Join-Path $RepositoryRoot (
    "var_cache\_test\release-$([Guid]::NewGuid().ToString('N'))"
)
$EntryRoot = Join-Path $TestRoot 'var_entry\hello'
try {
    [void][IO.Directory]::CreateDirectory($EntryRoot)
    $Context = New-SwawHarnessWindowsBootstrapContext -VarRoot $VarRoot
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $Context `
        -Contract $Contract
    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $Context `
        -Contract $Contract `
        -InstallRoot $InstallRoot
    if ($null -eq $Toolchain) {
        throw 'Release test requires the Contract toolchain to be installed.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $Context `
        -Contract $Contract `
        -Toolchain $Toolchain
    $CandidatePath = & (Join-Path $WindowsRoot 'build.ps1') `
        -VarRoot $TestRoot `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $First = & (Join-Path $WindowsRoot 'publish.ps1') `
        -VarRoot $TestRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1
    $Second = & (Join-Path $WindowsRoot 'publish.ps1') `
        -VarRoot $TestRoot `
        -EntryRoot $EntryRoot `
        -CandidatePath ([string]$CandidatePath) |
        Select-Object -Last 1

    Assert-ReleaseTest `
        -Condition ([string]$First.ReleaseId -ceq [string]$Second.ReleaseId) `
        -Message 'idempotent publication changed the Release ID'
    $ReleaseDirectories = @(
        Get-ChildItem -LiteralPath (Join-Path $EntryRoot 'releases') `
            -Directory `
            -Force
    )
    Assert-ReleaseTest `
        -Condition ($ReleaseDirectories.Count -eq 1) `
        -Message 'idempotent publication created duplicate Releases'
    $Selector = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-ReleaseTest `
        -Condition ($Selector -ceq [string]$First.ReleaseId) `
        -Message 'target selector does not reference the published Release'

    $Executable = Join-Path `
        ([string]$First.ReleaseRoot) `
        'swaw-harness-helloworld.exe'
    $Output = & $Executable 'Bootstrap'
    Assert-ReleaseTest `
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
        & (Join-Path $WindowsRoot 'publish.ps1') `
            -VarRoot $TestRoot `
            -EntryRoot $EntryRoot `
            -CandidatePath ([string]$CandidatePath) | Out-Null
    } catch {
        $Rejected = $true
    }
    Assert-ReleaseTest `
        -Condition $Rejected `
        -Message 'publication accepted a tampered candidate descriptor'
    $SelectorAfterFailure = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-ReleaseTest `
        -Condition ($SelectorAfterFailure -ceq [string]$First.ReleaseId) `
        -Message 'failed publication changed the previous selector'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap Release' -ForegroundColor Green
