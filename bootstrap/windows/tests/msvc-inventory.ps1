$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot '_lib\contract.ps1')
. (Join-Path $WindowsRoot '_lib\filesystem.ps1')
. (Join-Path $WindowsRoot '_lib\toolchain\msvc\inventory.ps1')

function Assert-MsvcInventoryTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
$TestBase = Join-Path $RepositoryRoot 'var_cache\_test'
[void][IO.Directory]::CreateDirectory($TestBase)
$TestRoot = Join-Path $TestBase (
    "msvc-inventory-$([Guid]::NewGuid().ToString('N'))"
)
[void][IO.Directory]::CreateDirectory($TestRoot)
try {
    $ToolVersion = '14.51.36231'
    $SdkVersion = '10.0.28000.0'
    foreach ($RelativePath in Get-SwawHarnessMsvcRequiredPaths `
        -ToolVersion $ToolVersion `
        -SdkVersion $SdkVersion) {
        $Path = Resolve-SwawHarnessChildPath `
            -Root $TestRoot `
            -RelativePath $RelativePath `
            -Description 'MSVC inventory fixture'
        [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
        [IO.File]::WriteAllText(
            $Path,
            "fixture:$RelativePath",
            [Text.UTF8Encoding]::new($false)
        )
    }
    $Payload = [pscustomobject]@{
        FileName = 'fixture.vsix'
        LeafName = 'fixture.vsix'
        Url = 'https://download.visualstudio.microsoft.com/fixture.vsix'
        DeclaredSize = 123
        Length = 120
        Sha256 = Get-SwawHarnessTextSha256 -Value 'fixture-vsix'
    }
    $Recipe = [pscustomobject]@{
        ManifestUrl = [string]$Contract.MsvcManifestUrl
        ManifestLength = [long]$Contract.MsvcManifestLength
        ManifestSha256 = [string]$Contract.MsvcManifestSha256
        ToolPackageVersion = '14.51'
        SdkPackageId = 'Win11SDK_10'
    }
    $Versions = [pscustomobject]@{
        ToolVersion = $ToolVersion
        SdkVersion = $SdkVersion
    }
    $Record = New-SwawHarnessMsvcInstallRecord `
        -Contract $Contract `
        -Recipe $Recipe `
        -Versions $Versions `
        -UsedPayloads @($Payload) `
        -MsvcRoot $TestRoot `
        -ControlledRoot $TestBase
    Assert-MsvcInventoryTest `
        -Condition (Test-SwawHarnessMsvcInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -MsvcRoot $TestRoot `
            -ControlledRoot $TestBase) `
        -Message 'MSVC fixture failed its fast receipt check.'
    Assert-MsvcInventoryTest `
        -Condition (Test-SwawHarnessMsvcInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -MsvcRoot $TestRoot `
            -ControlledRoot $TestBase `
            -Full) `
        -Message 'MSVC fixture failed its full audit.'
    Assert-MsvcInventoryTest `
        -Condition (
            $null -eq $Record.PSObject.Properties['files'] -and
            @($Record.criticalFiles).Count -eq
                @(Get-SwawHarnessMsvcRequiredPaths `
                    -ToolVersion $ToolVersion `
                    -SdkVersion $SdkVersion).Count
        ) `
        -Message 'MSVC receipt still stores the complete file inventory.'
    Assert-MsvcInventoryTest `
        -Condition (
            [string]$Record.productLine -ceq 'vs2026' -and
            [string]$Record.license.url -ceq
                [string]$Contract.MsvcLicenseUrl -and
            [string]$Record.license.acceptance -ceq
                'by-bootstrap-invocation'
        ) `
        -Message 'MSVC receipt omitted its product line or license contract.'
    $Record.license.acceptance = 'interactive'
    Assert-MsvcInventoryTest `
        -Condition (-not (Test-SwawHarnessMsvcInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -MsvcRoot $TestRoot `
            -ControlledRoot $TestBase)) `
        -Message 'MSVC receipt accepted a changed license policy.'
    $Record.license.acceptance = [string]$Contract.MsvcLicenseAcceptance

    $Unexpected = Join-Path $TestRoot 'unexpected.txt'
    [IO.File]::WriteAllText($Unexpected, 'unexpected')
    Assert-MsvcInventoryTest `
        -Condition (
            (Test-SwawHarnessMsvcInstallRecord `
                -Record $Record `
                -Contract $Contract `
                -MsvcRoot $TestRoot `
                -ControlledRoot $TestBase) -and
            -not (Test-SwawHarnessMsvcInstallRecord `
                -Record $Record `
                -Contract $Contract `
                -MsvcRoot $TestRoot `
                -ControlledRoot $TestBase `
                -Full)
        ) `
        -Message 'MSVC fast/full inventory boundary is incorrect.'
    [IO.File]::Delete($Unexpected)

    [IO.File]::AppendAllText(
        (Join-Path $TestRoot (
            "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\cl.exe"
        )),
        'damage'
    )
    Assert-MsvcInventoryTest `
        -Condition (-not (Test-SwawHarnessMsvcInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -MsvcRoot $TestRoot `
            -ControlledRoot $TestBase)) `
        -Message 'MSVC inventory accepted compiler corruption.'

    Write-Host '[PASS] MSVC inventory test' -ForegroundColor Green
} finally {
    Remove-SwawHarnessControlledPathWithRetry `
        -Path $TestRoot `
        -ControlledRoot $TestBase `
        -Activity 'cleaning the MSVC inventory test'
}
