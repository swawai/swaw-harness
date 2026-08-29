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
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$FixtureParent = Split-Path -Path $RepositoryRoot -Parent
$Token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$LeafPrefix = "swaw-path-$Token-"
$LeafLength = 60 - $FixtureParent.Length - 1
if ($LeafLength -lt $LeafPrefix.Length) {
    throw "Cannot place path-budget fixtures below: $FixtureParent"
}
$BoundaryLeaf = $LeafPrefix + ('b' * ($LeafLength - $LeafPrefix.Length))
$BoundaryRoot = [IO.Path]::GetFullPath((
    Join-Path $FixtureParent $BoundaryLeaf
))
$OverlongRoot = $BoundaryRoot + 'x'
$OverlongChild = Join-Path $OverlongRoot 'repo'
$AliasRoot = [IO.Path]::GetFullPath((
    Join-Path $FixtureParent "swaw-alias-$Token"
))
$AliasChild = Join-Path $AliasRoot 'repo'

Assert-PathBudgetTest `
    -Condition (
        $BoundaryRoot.Length -eq 60 -and
        $OverlongRoot.Length -eq 61 -and
        $AliasChild.Length -le 60
    ) `
    -Message 'physical path fixtures do not exercise the 60-character boundary'

try {
    [void][IO.Directory]::CreateDirectory($BoundaryRoot)
    [void][IO.Directory]::CreateDirectory($OverlongChild)
    [void](New-Item `
        -ItemType Junction `
        -Path $AliasRoot `
        -Target $OverlongRoot `
        -ErrorAction Stop)

    [void](Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot $BoundaryRoot)
    $DataRepo = Join-Path $BoundaryRoot 'data.repo'
    $Context = [pscustomobject][ordered]@{
        HarnessRoot = $BoundaryRoot
        DataRepo = $DataRepo
        RustupStageRoot = Join-Path $DataRepo 'windows.stage\rustup'
        ToolchainRoot = Join-Path $DataRepo 'windows.tool'
        StageRoot = Join-Path $DataRepo 'windows.stage'
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
        $TargetRoot = Join-Path $DataRepo (
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

    $RuntimeMsvcPath = Join-Path $BoundaryRoot (
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
            -RepositoryRoot $OverlongRoot)
    } catch {
        $OverlongRepositoryRejected = $_.Exception.Message -match 'measured 61'
    }
    Assert-PathBudgetTest `
        -Condition $OverlongRepositoryRejected `
        -Message 'a 61-character repository root was not rejected early'

    $AliasRepositoryRejected = $false
    try {
        [void](Assert-SwawHarnessRepositoryRootPathBudget `
            -RepositoryRoot $AliasChild)
    } catch {
        $AliasRepositoryRejected = $_.Exception.Message -match (
            'reparse point|direct long physical path'
        )
    }
    Assert-PathBudgetTest `
        -Condition $AliasRepositoryRejected `
        -Message 'a short reparse-point view bypassed the physical root budget'

    foreach ($EntryPoint in @(
        'main.ps1',
        'toolchain-setup.ps1',
        'toolchain.ps1',
        'core\build.ps1',
        'entry\build.ps1',
        'entry.manager\build.ps1'
    )) {
        $Command = Get-Command (Join-Path $WindowsRoot $EntryPoint)
        Assert-PathBudgetTest `
            -Condition (-not $Command.Parameters.ContainsKey('DataRepo')) `
            -Message "$EntryPoint still exposes a production DataRepo override"
    }

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
} finally {
    if ([IO.Directory]::Exists($AliasRoot)) {
        [IO.Directory]::Delete($AliasRoot, $false)
    }
    if ([IO.Directory]::Exists($OverlongChild)) {
        [IO.Directory]::Delete($OverlongChild, $false)
    }
    if ([IO.Directory]::Exists($OverlongRoot)) {
        [IO.Directory]::Delete($OverlongRoot, $false)
    }
    if ([IO.Directory]::Exists($BoundaryRoot)) {
        [IO.Directory]::Delete($BoundaryRoot, $false)
    }
}
