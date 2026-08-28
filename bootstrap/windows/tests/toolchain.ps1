[CmdletBinding()]
param([string]$DataRoot = '')

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
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRoot = Resolve-SwawHarnessWindowsTestDataRoot `
    -DataRoot $DataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRoot $DataRoot
$PreviousRustFlags = [Environment]::GetEnvironmentVariable('RUSTFLAGS', 'Process')
try {
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRoot $TestRoot
    $ExpectedOwnerRoot = [IO.Path]::GetFullPath(
        (Join-Path $TestRoot 'bootstrap.windows')
    )
    $ExpectedCacheRoot = [IO.Path]::GetFullPath(
        (Join-Path $TestRoot 'bootstrap.windows.cache')
    )
    $ExpectedNativeRoot = [IO.Path]::GetFullPath(
        (Join-Path $TestRoot 'n')
    )
    Assert-ToolchainTest `
        -Condition (
            [string]$Context.BootstrapWindowsRoot -ceq $ExpectedOwnerRoot -and
            [string]$Context.BootstrapWindowsCacheRoot -ceq
                $ExpectedCacheRoot -and
            [string]$Context.NativeRoot -ceq $ExpectedNativeRoot -and
            [string]$Context.NativeInstallRoot -ceq
                (Join-Path $TestRoot 'i') -and
            [string]$Context.ToolchainRoot -ceq
                (Join-Path $ExpectedNativeRoot 't') -and
            [string]$Context.WorkRoot -ceq
                (Join-Path $ExpectedNativeRoot 'w') -and
            [string]$Context.NativeBuildRoot -ceq
                (Join-Path $ExpectedNativeRoot 'b') -and
            [string]$Context.LockRoot -ceq
                (Join-Path $ExpectedOwnerRoot 'locks') -and
            [string]$Context.LogRoot -ceq
                (Join-Path $ExpectedOwnerRoot 'logs') -and
            [string]$Context.DownloadRoot -ceq
                (Join-Path $ExpectedCacheRoot 'downloads') -and
            [string]$Context.CargoHome -ceq
                (Join-Path $ExpectedNativeRoot 'c') -and
            [string]$Context.BootstrapReleaseRoot -ceq
                (Join-Path $TestRoot 'bootstrap.release') -and
            -not (Test-Path -LiteralPath (Join-Path $TestRoot 'cache'))
        ) `
        -Message 'Bootstrap state and cache roots were not kept distinct'
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $PathBudgetAccepted = $false
    try {
        $BoundaryRoot = 'C:\' + ('a' * 87)
        [void](Assert-SwawHarnessRepositoryRootPathBudget `
            -RepositoryRoot $BoundaryRoot)
        $PathBudgetAccepted = $true
    } catch {
        $PathBudgetAccepted = $false
    }
    Assert-ToolchainTest `
        -Condition $PathBudgetAccepted `
        -Message 'repository-root path budget rejected its 90-character boundary'
    $PathBudgetRejected = $false
    try {
        [void](Assert-SwawHarnessRepositoryRootPathBudget `
            -RepositoryRoot ('C:\' + ('a' * 88)))
    } catch {
        $PathBudgetRejected = $_.Exception.Message -like (
            'Windows Bootstrap supports an absolute repository root no longer*'
        )
    }
    Assert-ToolchainTest `
        -Condition $PathBudgetRejected `
        -Message 'repository-root path budget accepted 91 characters'
    $RustupContent = 'rustup fixture'
    $Contract.RustupInitLength = [Text.Encoding]::UTF8.GetByteCount(
        $RustupContent
    )
    $Contract.RustupInitSha256 = Get-SwawHarnessTextSha256 `
        -Value $RustupContent
    $ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
    $CollisionId = $ToolchainId.Substring(0, 7) +
        $(if ($ToolchainId[7] -ceq 'f') { 'e' } else { 'f' }) +
        $ToolchainId.Substring(8)
    $CollisionRoot = Join-Path $Context.ToolchainRoot (
        $ToolchainId.Substring(0, 7)
    )
    [void][IO.Directory]::CreateDirectory($CollisionRoot)
    [IO.File]::WriteAllText(
        (Join-Path $CollisionRoot 'toolchain.json'),
        (ConvertTo-SwawHarnessJsonText -Value ([ordered]@{
            toolchainId = $CollisionId
        })),
        [Text.UTF8Encoding]::new($false)
    )
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $Context `
        -Contract $Contract
    Assert-ToolchainTest `
        -Condition (
            [IO.Path]::GetFileName($InstallRoot) -ceq
                $ToolchainId.Substring(0, 8)
        ) `
        -Message 'toolchain locator did not grow after a 7-character collision'
    $RustRoot = Join-Path $InstallRoot 'r'
    $MsvcRoot = Join-Path $InstallRoot 'm'
    [void][IO.Directory]::CreateDirectory($RustRoot)
    [void][IO.Directory]::CreateDirectory($MsvcRoot)

    foreach ($RelativePath in Get-SwawHarnessRustRequiredPaths `
        -Contract $Contract) {
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
        -ControlledRoot $Context.NativeRoot

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
        -ControlledRoot $Context.NativeRoot
    $Metadata = [ordered]@{
        schema = 'swaw.harness.bootstrap.toolchain/v4'
        toolchainId = $ToolchainId
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
            -not $Plan.EnvironmentVariables.Contains('RUSTUP_HOME') -and
            -not $Plan.EnvironmentVariables.Contains('RUSTUP_TOOLCHAIN') -and
            [string]$Plan.CargoPath -ceq
                (Join-Path $RustRoot 'bin\cargo.exe') -and
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
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}
