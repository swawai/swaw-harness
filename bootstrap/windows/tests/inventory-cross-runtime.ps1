$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot '_lib\contract.ps1')
. (Join-Path $WindowsRoot '_lib\filesystem.ps1')
. (Join-Path $WindowsRoot '_lib\toolchain\rust\inventory.ps1')
. (Join-Path $WindowsRoot '_lib\toolchain\msvc\inventory.ps1')

function Write-CrossRuntimeFile {
    param([string]$Root, [string]$RelativePath, [string]$Content)

    $Path = Resolve-SwawHarnessChildPath `
        -Root $Root `
        -RelativePath $RelativePath `
        -Description 'cross-runtime fixture file'
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText(
        $Path,
        $Content,
        [Text.UTF8Encoding]::new($false)
    )
}

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
$TestBase = Join-Path $RepositoryRoot 'var_cache\_test'
[void][IO.Directory]::CreateDirectory($TestBase)
$TestRoot = Join-Path $TestBase (
    "cross-runtime-$([Guid]::NewGuid().ToString('N'))"
)
$ControlledRoot = Join-Path $TestRoot 'controlled'
$RustRoot = Join-Path $ControlledRoot 'rust'
$MsvcRoot = Join-Path $ControlledRoot 'msvc'
[void][IO.Directory]::CreateDirectory($RustRoot)
[void][IO.Directory]::CreateDirectory($MsvcRoot)
try {
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $RustupContent = 'cross-runtime rustup fixture'
    $Contract.RustupInitLength = [Text.Encoding]::UTF8.GetByteCount(
        $RustupContent
    )
    $Contract.RustupInitSha256 = Get-SwawHarnessTextSha256 `
        -Value $RustupContent
    Write-CrossRuntimeFile `
        -Root $RustRoot `
        -RelativePath 'cargo\bin\rustup.exe' `
        -Content $RustupContent
    foreach ($RelativePath in Get-SwawHarnessRustRequiredPaths `
        -Contract $Contract) {
        if ($RelativePath -ceq 'cargo\bin\rustup.exe') {
            continue
        }
        Write-CrossRuntimeFile `
            -Root $RustRoot `
            -RelativePath $RelativePath `
            -Content "rust:$RelativePath"
    }
    foreach ($RelativePath in @(
        'rustup\sort\A.txt',
        'rustup\sort\a-1.txt',
        'rustup\sort\[first].txt',
        'rustup\sort\_last.txt'
    )) {
        Write-CrossRuntimeFile `
            -Root $RustRoot `
            -RelativePath $RelativePath `
            -Content "sort:$RelativePath"
    }
    $ProxyBin = Join-Path $RustRoot 'cargo\bin'
    foreach ($ProxyName in @('cargo.exe', 'cargo-miri.exe', 'rustc.exe')) {
        $ProxyPath = Join-Path $ProxyBin $ProxyName
        if ([IO.File]::Exists($ProxyPath)) {
            [IO.File]::Delete($ProxyPath)
        }
        Push-Location $ProxyBin
        try {
            & $env:ComSpec /d /c (
                "mklink `"$ProxyName`" rustup.exe"
            ) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Cannot create cross-runtime proxy: $ProxyName"
            }
        } finally {
            Pop-Location
        }
    }
    $RustRecord = New-SwawHarnessRustInstallRecord `
        -Contract $Contract `
        -Probe ([pscustomobject][ordered]@{
            rustupVersion = [string]$Contract.RustupInitVersion
            rustcVersion = [string]$Contract.RustToolchain
            rustcCommit = '1111111111111111111111111111111111111111'
            cargoVersion = [string]$Contract.RustToolchain
            host = [string]$Contract.TargetId
        }) `
        -RustRoot $RustRoot `
        -ControlledRoot $ControlledRoot

    $ToolVersion = '14.51.36231'
    $SdkVersion = '10.0.28000.0'
    foreach ($RelativePath in Get-SwawHarnessMsvcRequiredPaths `
        -ToolVersion $ToolVersion `
        -SdkVersion $SdkVersion) {
        Write-CrossRuntimeFile `
            -Root $MsvcRoot `
            -RelativePath $RelativePath `
            -Content "msvc:$RelativePath"
    }
    foreach ($RelativePath in @(
        'sort\A.txt', 'sort\a-1.txt', 'sort\[first].txt', 'sort\_last.txt'
    )) {
        Write-CrossRuntimeFile `
            -Root $MsvcRoot `
            -RelativePath $RelativePath `
            -Content "sort:$RelativePath"
    }
    $MsvcRecord = New-SwawHarnessMsvcInstallRecord `
        -Contract $Contract `
        -Recipe ([pscustomobject]@{
            ManifestUrl = [string]$Contract.MsvcManifestUrl
            ManifestLength = [long]$Contract.MsvcManifestLength
            ManifestSha256 = [string]$Contract.MsvcManifestSha256
            ToolPackageVersion = '14.51'
            SdkPackageId = 'Win11SDK_10'
        }) `
        -Versions ([pscustomobject]@{
            ToolVersion = $ToolVersion
            SdkVersion = $SdkVersion
        }) `
        -UsedPayloads @([pscustomobject]@{
            FileName = 'fixture.vsix'
            LeafName = 'fixture.vsix'
            Url = 'https://download.visualstudio.microsoft.com/fixture.vsix'
            DeclaredSize = 123
            Length = 120
            Sha256 = Get-SwawHarnessTextSha256 -Value 'fixture-vsix'
        }) `
        -MsvcRoot $MsvcRoot `
        -ControlledRoot $ControlledRoot

    $RustRecordPath = Join-Path $TestRoot 'rust.json'
    $MsvcRecordPath = Join-Path $TestRoot 'msvc.json'
    [IO.File]::WriteAllText(
        $RustRecordPath,
        (ConvertTo-SwawHarnessJsonText -Value $RustRecord),
        [Text.UTF8Encoding]::new($false)
    )
    [IO.File]::WriteAllText(
        $MsvcRecordPath,
        (ConvertTo-SwawHarnessJsonText -Value $MsvcRecord),
        [Text.UTF8Encoding]::new($false)
    )
    & 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File (Join-Path $PSScriptRoot 'inventory-cross-runtime-child.ps1') `
        -ControlledRoot $ControlledRoot `
        -RustRoot $RustRoot `
        -MsvcRoot $MsvcRoot `
        -RustRecordPath $RustRecordPath `
        -MsvcRecordPath $MsvcRecordPath `
        -RustupLength ([long]$Contract.RustupInitLength) `
        -RustupSha256 ([string]$Contract.RustupInitSha256)
    if ($LASTEXITCODE -ne 0) {
        throw 'PowerShell 5.1 rejected PowerShell 7 inventory records.'
    }
    Write-Host '[PASS] Cross-runtime inventory ordering' -ForegroundColor Green
} finally {
    Remove-SwawHarnessControlledPathWithRetry `
        -Path $TestRoot `
        -ControlledRoot $TestBase `
        -Activity 'cleaning the cross-runtime inventory test'
}
