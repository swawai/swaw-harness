[CmdletBinding()]
param([string]$RepositoryDataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\filesystem.ps1')
. (Join-Path $WindowsRoot 'toolchain\msvc\assembly.ps1')

function Assert-MsvcAssemblyTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$RepositoryDataRoot = Resolve-SwawHarnessWindowsTestRepositoryDataRoot `
    -RepositoryDataRoot $RepositoryDataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -RepositoryDataRoot $RepositoryDataRoot
$TestBase = Split-Path -Path $TestRoot -Parent
try {
    $ToolVersion = '14.51.36231'
    $SdkVersion = '10.0.28000.0'
    $ToolBin = Join-Path $TestRoot (
        "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64"
    )
    $DiaBin = Join-Path $TestRoot 'DIA SDK\bin\amd64'
    $SdkBin = Join-Path $TestRoot "Windows Kits\10\bin\$SdkVersion"
    foreach ($Directory in @(
        $ToolBin,
        $DiaBin,
        (Join-Path $SdkBin 'x64'),
        (Join-Path $SdkBin 'x86'),
        (Join-Path $TestRoot 'Common7'),
        (Join-Path $TestRoot (
            "Windows Kits\10\Lib\$SdkVersion\ucrt\x86"
        ))
    )) {
        [void][IO.Directory]::CreateDirectory($Directory)
    }
    [IO.File]::WriteAllText(
        (Join-Path $DiaBin 'msdia140.dll'),
        'dia',
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        (Join-Path $ToolBin 'vctip.exe'),
        'telemetry',
        [Text.UTF8Encoding]::new($false)
    )
    $Context = [pscustomobject]@{
        RepositoryDataRoot = $TestBase
        StageRoot = $TestBase
        LogRoot = $TestBase
    }
    $Versions = Complete-SwawHarnessMsvcAssembly `
        -Context $Context `
        -InstallRoot $TestRoot
    $Setup = [IO.File]::ReadAllText(
        (Join-Path $TestRoot 'setup_x64.bat'),
        [Text.Encoding]::UTF8
    )
    Assert-MsvcAssemblyTest `
        -Condition (
            [string]$Versions.ToolVersion -ceq $ToolVersion -and
            [string]$Versions.SdkVersion -ceq $SdkVersion -and
            [IO.File]::ReadAllText((Join-Path $ToolBin 'msdia140.dll')) -ceq
                'dia' -and
            -not [IO.File]::Exists((Join-Path $ToolBin 'vctip.exe')) -and
            -not [IO.Directory]::Exists((Join-Path $TestRoot 'Common7')) -and
            -not [IO.Directory]::Exists((Join-Path $SdkBin 'x86')) -and
            $Setup.Contains("VCToolsVersion=$ToolVersion") -and
            $Setup.Contains("WindowsSDKVersion=$SdkVersion\")
        ) `
        -Message 'Portable MSVC assembly lost its x64 layout contract.'

    Write-Host '[PASS] MSVC assembly test' -ForegroundColor Green
} finally {
    Remove-SwawHarnessControlledPathWithRetry `
        -Path $TestRoot `
        -ControlledRoot $TestBase `
        -Activity 'cleaning the MSVC assembly test'
}
