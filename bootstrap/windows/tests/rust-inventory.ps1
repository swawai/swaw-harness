[CmdletBinding()]
param([string]$DataRoot = '')

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
$DataRoot = Resolve-SwawHarnessWindowsTestDataRoot `
    -DataRoot $DataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRoot $DataRoot
$ControlledRoot = Join-Path $TestRoot 'controlled'
$RustRoot = Join-Path $ControlledRoot 'rust'
$JunctionPath = ''

try {
    [void][IO.Directory]::CreateDirectory($RustRoot)
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $RustupContent = 'rustup fixture bytes'
    Write-RustInventoryFixtureFile `
        -Root $RustRoot `
        -RelativePath 'cargo\bin\rustup.exe' `
        -Content $RustupContent
    $RustupPath = Join-Path $RustRoot 'cargo\bin\rustup.exe'
    $Contract.RustupInitLength = (Get-Item -LiteralPath $RustupPath).Length
    $Contract.RustupInitSha256 = Get-SwawHarnessFileSha256 -Path $RustupPath
    foreach ($RelativePath in Get-SwawHarnessRustRequiredPaths `
        -Contract $Contract) {
        if ($RelativePath -ceq 'cargo\bin\rustup.exe') {
            continue
        }
        Write-RustInventoryFixtureFile `
            -Root $RustRoot `
            -RelativePath $RelativePath `
            -Content "fixture:$RelativePath"
    }
    foreach ($ProxyName in @('cargo.exe', 'cargo-miri.exe', 'rustc.exe')) {
        $ProxyPath = Join-Path $RustRoot "cargo\bin\$ProxyName"
        if ([IO.File]::Exists($ProxyPath)) {
            [IO.File]::Delete($ProxyPath)
        }
        Push-Location (Split-Path $ProxyPath -Parent)
        try {
            & $env:ComSpec /d /c (
                "mklink `"$ProxyName`" rustup.exe"
            ) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Cannot create Rust proxy fixture: $ProxyName"
            }
        } finally {
            Pop-Location
        }
    }
    $Probe = [pscustomobject][ordered]@{
        rustupVersion = [string]$Contract.RustupInitVersion
        rustcVersion = [string]$Contract.RustToolchain
        rustcCommit = '1111111111111111111111111111111111111111'
        cargoVersion = '1.97.1'
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
    Assert-RustInventoryTest `
        -Condition (@(Get-SwawHarnessRustRequiredPaths `
            -Contract $Contract | Where-Object { $_ -like '*rustfmt*' }
        ).Count -eq 0) `
        -Message 'cold Rust contract still requires rustfmt'

    $CargoPath = Join-Path $RustRoot 'cargo\bin\cargo.exe'
    $CargoOriginal = [IO.File]::ReadAllText($CargoPath)
    [IO.File]::WriteAllText($CargoPath, 'tampered')
    Assert-RustInventoryTest `
        -Condition (-not (Test-SwawHarnessRustInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot)) `
        -Message 'Rust file tampering passed the recorded inventory'
    [IO.File]::WriteAllText(
        $CargoPath,
        $CargoOriginal,
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
    $JunctionPath = Join-Path $RustRoot 'rustup\linked'
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
