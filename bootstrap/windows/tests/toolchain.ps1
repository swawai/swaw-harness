$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')

function Assert-ToolchainTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Toolchain test failed: $Message"
    }
}

function Write-ToolchainFixtureFile {
    param([string]$Root, [string]$RelativePath, [string]$Content)

    $Path = Resolve-SwawHarnessChildPath `
        -Root $Root `
        -RelativePath $RelativePath `
        -Description 'toolchain fixture file'
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText(
        $Path,
        $Content,
        [Text.UTF8Encoding]::new($false)
    )
}

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
$DataRoot = Join-Path $RepositoryRoot (
    "data\bootstrap.windows.cache\_test\toolchain-$([Guid]::NewGuid().ToString('N'))"
)
[void][IO.Directory]::CreateDirectory($DataRoot)
$PreviousRustFlags = [Environment]::GetEnvironmentVariable('RUSTFLAGS', 'Process')
try {
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $DataRoot
    $ExpectedOwnerRoot = [IO.Path]::GetFullPath(
        (Join-Path $DataRoot 'bootstrap.windows')
    )
    $ExpectedCacheRoot = [IO.Path]::GetFullPath(
        (Join-Path $DataRoot 'bootstrap.windows.cache')
    )
    Assert-ToolchainTest `
        -Condition (
            [string]$Context.BootstrapWindowsRoot -ceq $ExpectedOwnerRoot -and
            [string]$Context.BootstrapWindowsCacheRoot -ceq
                $ExpectedCacheRoot -and
            [string]$Context.ToolchainRoot -ceq
                (Join-Path $ExpectedOwnerRoot 'toolchains') -and
            [string]$Context.WorkRoot -ceq
                (Join-Path $ExpectedOwnerRoot 'work') -and
            [string]$Context.LockRoot -ceq
                (Join-Path $ExpectedOwnerRoot 'locks') -and
            [string]$Context.LogRoot -ceq
                (Join-Path $ExpectedOwnerRoot 'logs') -and
            [string]$Context.DownloadRoot -ceq
                (Join-Path $ExpectedCacheRoot 'downloads') -and
            [string]$Context.CargoHome -ceq
                (Join-Path $ExpectedCacheRoot 'cargo') -and
            [string]$Context.BootstrapReleaseRoot -ceq
                (Join-Path $DataRoot 'bootstrap.release') -and
            -not (Test-Path -LiteralPath (Join-Path $DataRoot 'cache'))
        ) `
        -Message 'Bootstrap state and cache roots were not kept distinct'
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $PathBudgetRejected = $false
    try {
        [void](Get-SwawHarnessBootstrapToolchain `
            -Context ([pscustomobject]@{ DataRoot = ('x' * 51) }) `
            -Contract $Contract)
    } catch {
        $PathBudgetRejected = $_.Exception.Message -like (
            'Windows Bootstrap v4 requires a DataRoot path no longer than*'
        )
    }
    Assert-ToolchainTest `
        -Condition $PathBudgetRejected `
        -Message 'cold bootstrap did not enforce its Windows path budget'
    $RustupContent = 'rustup fixture'
    $Contract.RustupInitLength = [Text.Encoding]::UTF8.GetByteCount(
        $RustupContent
    )
    $Contract.RustupInitSha256 = Get-SwawHarnessTextSha256 `
        -Value $RustupContent
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $Context `
        -Contract $Contract
    $RustRoot = Join-Path $InstallRoot 'rust'
    $MsvcRoot = Join-Path $InstallRoot 'msvc'
    [void][IO.Directory]::CreateDirectory($RustRoot)
    [void][IO.Directory]::CreateDirectory($MsvcRoot)

    Write-ToolchainFixtureFile `
        -Root $RustRoot `
        -RelativePath 'cargo\bin\rustup.exe' `
        -Content $RustupContent
    foreach ($RelativePath in Get-SwawHarnessRustRequiredPaths `
        -Contract $Contract) {
        if ($RelativePath -ceq 'cargo\bin\rustup.exe') {
            continue
        }
        Write-ToolchainFixtureFile `
            -Root $RustRoot `
            -RelativePath $RelativePath `
            -Content "fixture:$RelativePath"
    }
    $Probe = [pscustomobject][ordered]@{
        rustupVersion = [string]$Contract.RustupInitVersion
        rustcVersion = [string]$Contract.RustToolchain
        rustcCommit = '1111111111111111111111111111111111111111'
        cargoVersion = [string]$Contract.RustToolchain
        host = [string]$Contract.PlatformTargetId
    }
    $RustRecord = New-SwawHarnessRustInstallRecord `
        -Contract $Contract `
        -Probe $Probe `
        -RustRoot $RustRoot `
        -ControlledRoot $Context.BootstrapWindowsRoot

    $ToolVersion = '14.51.36231'
    $SdkVersion = '10.0.28000.0'
    foreach ($RelativePath in Get-SwawHarnessMsvcRequiredPaths `
        -ToolVersion $ToolVersion `
        -SdkVersion $SdkVersion) {
        Write-ToolchainFixtureFile `
            -Root $MsvcRoot `
            -RelativePath $RelativePath `
            -Content "fixture:$RelativePath"
    }
    foreach ($RelativeDirectory in @(
        "VC\Tools\MSVC\$ToolVersion\lib\x64"
        "Windows Kits\10\bin\$SdkVersion\x64\ucrt"
        "Windows Kits\10\Include\$SdkVersion\shared"
        "Windows Kits\10\Include\$SdkVersion\winrt"
        "Windows Kits\10\Include\$SdkVersion\cppwinrt"
    )) {
        [void][IO.Directory]::CreateDirectory((Join-Path $MsvcRoot $RelativeDirectory))
    }
    $MsvcPayload = [pscustomobject]@{
        FileName = 'fixture.vsix'
        LeafName = 'fixture.vsix'
        Url = 'https://download.visualstudio.microsoft.com/fixture.vsix'
        DeclaredSize = 123
        Length = 120
        Sha256 = Get-SwawHarnessTextSha256 -Value 'fixture-vsix'
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
        -UsedPayloads @($MsvcPayload) `
        -MsvcRoot $MsvcRoot `
        -ControlledRoot $Context.BootstrapWindowsRoot
    $Metadata = [ordered]@{
        schema = 'swaw.harness.bootstrap.toolchain/v3'
        toolchainId = Get-SwawHarnessToolchainId -Contract $Contract
        platformTargetId = [string]$Contract.PlatformTargetId
        rust = $RustRecord
        msvc = $MsvcRecord
    }
    [IO.File]::WriteAllText(
        (Join-Path $InstallRoot 'toolchain.json'),
        (ConvertTo-SwawHarnessJsonText -Value $Metadata),
        [Text.UTF8Encoding]::new($false)
    )

    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $Context `
        -Contract $Contract `
        -InstallRoot $InstallRoot
    Assert-ToolchainTest `
        -Condition ($null -ne $Toolchain) `
        -Message 'complete combined toolchain was not trusted'
    Assert-ToolchainTest `
        -Condition (Test-SwawHarnessToolchainFullInventory `
            -Context $Context `
            -Contract $Contract `
            -InstallRoot $InstallRoot) `
        -Message 'combined toolchain failed its explicit full audit'
    [Environment]::SetEnvironmentVariable('RUSTFLAGS', 'ambient', 'Process')
    $EnvironmentBefore = [Environment]::GetEnvironmentVariables('Process')
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $Context `
        -Contract $Contract `
        -Toolchain $Toolchain
    $EnvironmentAfter = [Environment]::GetEnvironmentVariables('Process')
    $EnvironmentUnchanged = $EnvironmentBefore.Count -eq $EnvironmentAfter.Count
    if ($EnvironmentUnchanged) {
        foreach ($Name in [string[]]@($EnvironmentBefore.Keys)) {
            if (-not $EnvironmentAfter.Contains($Name) -or
                [string]$EnvironmentAfter[$Name] -cne
                    [string]$EnvironmentBefore[$Name]) {
                $EnvironmentUnchanged = $false
                break
            }
        }
    }
    Assert-ToolchainTest `
        -Condition (
            $EnvironmentUnchanged -and
            $Plan.EnvironmentVariables.Contains('CARGO_HOME') -and
            $Plan.EnvironmentVariables.Contains('Path') -and
            $Plan.UnsetEnvironmentVariables -contains 'RUSTFLAGS'
        ) `
        -Message 'environment plan mutated its parent or omitted isolation facts'

    $Unexpected = Join-Path $InstallRoot 'unexpected.txt'
    [IO.File]::WriteAllText($Unexpected, 'unexpected')
    Assert-ToolchainTest `
        -Condition ($null -eq (Get-SwawHarnessValidToolchain `
            -Context $Context `
            -Contract $Contract `
            -InstallRoot $InstallRoot)) `
        -Message 'combined toolchain accepted an unexpected top-level member'
    [IO.File]::Delete($Unexpected)

    [IO.File]::AppendAllText(
        (Join-Path $MsvcRoot (
            "VC\Tools\MSVC\$ToolVersion\bin\Hostx64\x64\cl.exe"
        )),
        'damage'
    )
    Assert-ToolchainTest `
        -Condition ($null -eq (Get-SwawHarnessValidToolchain `
            -Context $Context `
            -Contract $Contract `
            -InstallRoot $InstallRoot)) `
        -Message 'combined toolchain accepted component corruption'

    Write-Host '[PASS] Windows Bootstrap combined toolchain' -ForegroundColor Green
} finally {
    [Environment]::SetEnvironmentVariable(
        'RUSTFLAGS',
        $PreviousRustFlags,
        'Process'
    )
    if ([IO.Directory]::Exists($DataRoot)) {
        [IO.Directory]::Delete($DataRoot, $true)
    }
}
