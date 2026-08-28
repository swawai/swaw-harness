[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-PathBudgetTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Path budget test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$RepositoryRoot = 'C:\' + ('a' * 87)
[void](Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot $RepositoryRoot)
$DataRoot = Join-Path $RepositoryRoot 'data'
$NativeRoot = Join-Path $DataRoot 'n'
$Context = [pscustomobject][ordered]@{
    DataRoot = $DataRoot
    NativeRoot = $NativeRoot
    NativeInstallRoot = Join-Path $DataRoot 'i'
    ToolchainRoot = Join-Path $NativeRoot 't'
    WorkRoot = Join-Path $NativeRoot 'w'
}
$ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
Assert-SwawHarnessToolchainInstallPathBudget `
    -Context $Context `
    -Contract $Contract `
    -ToolchainId $ToolchainId

$CoreContract = [pscustomobject][ordered]@{
    PlatformTargetId = [string]$Contract.PlatformTargetId
    ProductPackage = 'swaw-harness-helloworld'
    ProductBinary = 'swaw-harness-helloworld.exe'
}
$EntryManagerContract = [pscustomobject][ordered]@{
    PlatformTargetId = [string]$Contract.PlatformTargetId
    ProductPackage = 'swaw-harness-entry-manager'
    ProductBinary = 'swaw-harness-entry-manager.exe'
}
foreach ($Build in @(
    [pscustomobject]@{ Contract = $CoreContract; Locator = 'c' }
    [pscustomobject]@{ Contract = $EntryManagerContract; Locator = 'm' }
)) {
    $TargetRoot = Join-Path $NativeRoot "b\$($Build.Locator)"
    [void](Assert-SwawHarnessNativePathBudget `
        -Paths (Get-SwawHarnessCargoPlannedPaths `
            -TargetRoot $TargetRoot `
            -PlatformTargetId $Build.Contract.PlatformTargetId `
            -Package $Build.Contract.ProductPackage `
            -Binary $Build.Contract.ProductBinary) `
        -Description '90-character repository Cargo plan')
}

$OverlongRepositoryRejected = $false
try {
    [void](Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot ('C:\' + ('a' * 88)))
} catch {
    $OverlongRepositoryRejected = $_.Exception.Message -match (
        'measured 91'
    )
}
Assert-PathBudgetTest `
    -Condition $OverlongRepositoryRejected `
    -Message 'a 91-character repository root was not rejected early'

$OverlongNativePathRejected = $false
try {
    [void](Assert-SwawHarnessNativePathBudget `
        -Paths @('C:\' + ('a' * 238)) `
        -Description 'Synthetic native path')
} catch {
    $OverlongNativePathRejected = $_.Exception.Message -match 'measured 241'
}
Assert-PathBudgetTest `
    -Condition $OverlongNativePathRejected `
    -Message 'a 241-character native path was not rejected early'

Write-Host '[PASS] Windows Bootstrap path budget' -ForegroundColor Green
