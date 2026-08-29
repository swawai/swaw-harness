[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-RustInventoryTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Rust inventory test failed: $Message"
    }
}

function Write-RustInventoryFixtureFile {
    param([string]$Root, [string]$RelativePath, [string]$Content)
    $Path = Join-Path $Root $RelativePath
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText(
        $Path,
        $Content,
        [Text.UTF8Encoding]::new($false)
    )
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\rust\inventory.ps1')
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
$ControlledRoot = Join-Path $TestRoot 'controlled'
$RustRoot = Join-Path $ControlledRoot 'rust'
$JunctionPath = ''

try {
    [void][IO.Directory]::CreateDirectory($RustRoot)
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    Assert-RustInventoryTest `
        -Condition (
            [string]::Join(',', $Contract.RustComponents) -ceq
                'clippy,rustfmt'
        ) `
        -Message 'Windows Contract omitted the canonical Rust components'
    $InvalidContract = ConvertFrom-Json -InputObject (Get-Content `
        -Raw `
        -LiteralPath (Join-Path $WindowsRoot 'contract.json'))
    $InvalidContract.rust.components = @('rustfmt', 'clippy')
    $InvalidContractPath = Join-Path $TestRoot 'invalid-contract.json'
    [IO.File]::WriteAllText(
        $InvalidContractPath,
        (ConvertTo-SwawHarnessJsonText -Value $InvalidContract),
        [Text.UTF8Encoding]::new($false)
    )
    $RejectedInvalidContract = $false
    try {
        [void](Read-SwawHarnessWindowsBootstrapContract `
            -Path $InvalidContractPath)
    } catch {
        $RejectedInvalidContract = $true
    }
    Assert-RustInventoryTest `
        -Condition $RejectedInvalidContract `
        -Message 'Windows Contract accepted non-canonical Rust components'
    $OriginalDefinitionId = Get-SwawHarnessRustDefinitionId `
        -Contract $Contract
    $ChangedContract = $Contract.PSObject.Copy()
    $ChangedContract.RustComponents = [string[]]@('rustfmt')
    Assert-RustInventoryTest `
        -Condition (
            (Get-SwawHarnessRustDefinitionId -Contract $ChangedContract) -cne
                $OriginalDefinitionId
        ) `
        -Message 'Rust component change did not change its definition identity'
    $RustupContent = 'rustup fixture bytes'
    $Contract.RustupInitLength = [Text.Encoding]::UTF8.GetByteCount(
        $RustupContent
    )
    $Contract.RustupInitSha256 = Get-SwawHarnessTextSha256 `
        -Value $RustupContent
    foreach ($RelativePath in Get-SwawHarnessRustRequiredPaths `
        -Contract $Contract) {
        Write-RustInventoryFixtureFile `
            -Root $RustRoot `
            -RelativePath $RelativePath `
            -Content "fixture:$RelativePath"
    }
    $Probe = [pscustomobject][ordered]@{
        rustupVersion = [string]$Contract.RustupInitVersion
        rustcVersion = [string]$Contract.RustToolchain
        rustcCommit = '1111111111111111111111111111111111111111'
        cargoVersion = '1.97.1'
        rustfmtVersion = '1.8.0-stable'
        clippyVersion = '0.1.97'
        host = [string]$Contract.PlatformTargetId
    }
    $Record = New-SwawHarnessRustInstallRecord `
        -Contract $Contract `
        -Probe $Probe `
        -RustRoot $RustRoot `
        -ControlledRoot $ControlledRoot
    Assert-RustInventoryTest `
        -Condition (Test-SwawHarnessRustInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot) `
        -Message 'fresh Rust receipt failed its fast validation'
    Assert-RustInventoryTest `
        -Condition (Test-SwawHarnessRustInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot `
            -Full) `
        -Message 'fresh Rust receipt failed its full audit'
    Assert-RustInventoryTest `
        -Condition (
            $null -eq $Record.PSObject.Properties['files'] -and
            @($Record.criticalFiles).Count -eq
                @(Get-SwawHarnessRustRequiredPaths -Contract $Contract).Count
        ) `
        -Message 'Rust receipt still stores the complete file inventory'
    $RequiredPaths = [string[]]@(Get-SwawHarnessRustRequiredPaths `
        -Contract $Contract)
    foreach ($ComponentPath in @(
        'bin\cargo-clippy.exe',
        'bin\clippy-driver.exe',
        'bin\cargo-fmt.exe',
        'bin\rustfmt.exe'
    )) {
        Assert-RustInventoryTest `
            -Condition ($RequiredPaths -ccontains $ComponentPath) `
            -Message "Rust contract omitted component file $ComponentPath"
    }

    $CargoFmtPath = Join-Path $RustRoot 'bin\cargo-fmt.exe'
    $CargoFmtOriginal = [IO.File]::ReadAllText($CargoFmtPath)
    [IO.File]::WriteAllText($CargoFmtPath, 'tampered')
    Assert-RustInventoryTest `
        -Condition (-not (Test-SwawHarnessRustInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot)) `
        -Message 'Rust file tampering passed the recorded inventory'
    [IO.File]::WriteAllText(
        $CargoFmtPath,
        $CargoFmtOriginal,
        [Text.UTF8Encoding]::new($false)
    )

    $Unexpected = Join-Path $RustRoot 'unexpected.exe'
    [IO.File]::WriteAllText($Unexpected, 'unexpected')
    Assert-RustInventoryTest `
        -Condition (
            (Test-SwawHarnessRustInstallRecord `
                -Record $Record `
                -Contract $Contract `
                -RustRoot $RustRoot `
                -ControlledRoot $ControlledRoot) -and
            -not (Test-SwawHarnessRustInstallRecord `
                -Record $Record `
                -Contract $Contract `
                -RustRoot $RustRoot `
                -ControlledRoot $ControlledRoot `
                -Full)
        ) `
        -Message 'Rust fast/full inventory boundary is incorrect'
    [IO.File]::Delete($Unexpected)

    $Malformed = ConvertFrom-Json -InputObject (
        $Record | ConvertTo-Json -Depth 12
    )
    $Malformed | Add-Member -NotePropertyName unknown -NotePropertyValue 1
    Assert-RustInventoryTest `
        -Condition (-not (Test-SwawHarnessRustInstallRecord `
            -Record $Malformed `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot)) `
        -Message 'Rust record accepted an unknown field'

    $ExternalRoot = Join-Path $TestRoot 'external'
    [void][IO.Directory]::CreateDirectory($ExternalRoot)
    $Sentinel = Join-Path $ExternalRoot 'sentinel.txt'
    [IO.File]::WriteAllText($Sentinel, 'preserve')
    $JunctionPath = Join-Path $RustRoot 'linked'
    [void](New-Item `
        -ItemType Junction `
        -Path $JunctionPath `
        -Target $ExternalRoot)
    Assert-RustInventoryTest `
        -Condition ((Test-SwawHarnessRustInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot) -and
            -not (Test-SwawHarnessRustInstallRecord `
                -Record $Record `
                -Contract $Contract `
                -RustRoot $RustRoot `
                -ControlledRoot $ControlledRoot `
                -Full) -and
            [IO.File]::Exists($Sentinel)) `
        -Message 'Rust fast/full junction boundary is incorrect'
    [IO.Directory]::Delete($JunctionPath)
    $JunctionPath = ''
} finally {
    if (-not [string]::IsNullOrWhiteSpace($JunctionPath) -and
        [IO.Directory]::Exists($JunctionPath)) {
        [IO.Directory]::Delete($JunctionPath)
    }
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap Rust inventory' -ForegroundColor Green
