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
$RepositoryRoot = 'C:\' + ('a' * 57)
[void](Assert-SwawHarnessRepositoryRootPathBudget `
    -RepositoryRoot $RepositoryRoot)
$RepositoryDataRoot = Join-Path $RepositoryRoot 'data.repo'
$Context = [pscustomobject][ordered]@{
    HarnessRoot = $RepositoryRoot
    RepositoryDataRoot = $RepositoryDataRoot
    RustupStageRoot = Join-Path $RepositoryDataRoot 'windows.stage\rustup'
    ToolchainRoot = Join-Path $RepositoryDataRoot 'windows.tool'
    StageRoot = Join-Path $RepositoryDataRoot 'windows.stage'
}
$ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
Assert-SwawHarnessToolchainInstallPathBudget `
    -Context $Context `
    -Contract $Contract `
    -ToolchainId $ToolchainId

$CoreContract = [pscustomobject][ordered]@{
    PlatformTargetId = [string]$Contract.PlatformTargetId
    ProductPackage = 'swaw-harness-helloworld'
    BuildBinary = 'swaw-harness-helloworld.exe'
    ProductBinary = 'swaw-harness-helloworld.exe'
}
$EntryManagerContract = [pscustomobject][ordered]@{
    PlatformTargetId = [string]$Contract.PlatformTargetId
    ProductPackage = 'swaw-har-manager'
    BuildBinary = 'swaw-har-manager.exe'
    ProductBinary = 'swaw-harness-entry-manager.exe'
}
foreach ($Build in @(
    [pscustomobject]@{ Contract = $CoreContract; Product = 'core' }
    [pscustomobject]@{ Contract = $EntryManagerContract; Product = 'manager' }
)) {
    $TargetRoot = Join-Path $RepositoryDataRoot (
        "windows.build\$($Build.Product)"
    )
    [void](Assert-SwawHarnessNativePathBudget `
        -Paths (Get-SwawHarnessCargoPlannedPaths `
            -TargetRoot $TargetRoot `
            -PlatformTargetId $Build.Contract.PlatformTargetId `
            -Package $Build.Contract.ProductPackage `
            -Binary $Build.Contract.BuildBinary) `
        -Description '60-character repository Cargo plan')
}

$RuntimeMsvcPath = Join-Path $RepositoryRoot (
    "data\$('e' * 16)\release\dev\setup\$('a' * 12)\m\" +
    'Windows Kits\10\Include\10.0.28000.0\cppwinrt\winrt\impl\' +
    'windows.applicationmodel.appointments.appointmentsprovider.0.h'
)
Assert-PathBudgetTest `
    -Condition ($RuntimeMsvcPath.Length -eq 235) `
    -Message 'the reserved Entry runtime MSVC path is not 235 characters'

$OverlongRepositoryRejected = $false
try {
    [void](Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot ('C:\' + ('a' * 58)))
} catch {
    $OverlongRepositoryRejected = $_.Exception.Message -match (
        'measured 61'
    )
}
Assert-PathBudgetTest `
    -Condition $OverlongRepositoryRejected `
    -Message 'a 61-character repository root was not rejected early'

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
