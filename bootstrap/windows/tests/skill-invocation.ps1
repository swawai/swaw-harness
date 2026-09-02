[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $WindowsRoot 'core\candidate-build.ps1')
. (Join-Path $WindowsRoot 'core\contract.ps1')
. (Join-Path $WindowsRoot 'module-publication.ps1')
. (Join-Path $WindowsRoot 'host\candidate-build.ps1')
. (Join-Path $WindowsRoot 'admin-initialization.ps1')
. (Join-Path $WindowsRoot 'user\candidate-build.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
    -Path (Join-Path $WindowsRoot 'core\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId)
$HelloworldContracts = @($CoreContracts | Where-Object {
    $_.ModuleId -ceq 'swaw/templates/helloworld'
})
$DevContracts = @($CoreContracts | Where-Object {
    $_.ModuleId -ceq 'swaw/core/dev'
})
if ($HelloworldContracts.Count -ne 1 -or $DevContracts.Count -ne 1) {
    throw 'Skill invocation test requires one Helloworld and one Dev contract.'
}
$HelloworldContract = $HelloworldContracts[0]
$DevContract = $DevContracts[0]
$HostContract = Read-SwawHarnessWindowsCoreHostContract `
    -Path (Join-Path $WindowsRoot 'host\contract.json') `
    -PlatformTargetId $PlatformContract.PlatformTargetId

$SharedContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
$Toolchain = Get-SwawHarnessBootstrapToolchain `
    -Context $SharedContext `
    -Contract $PlatformContract
$Plan = Get-SwawHarnessToolchainEnvironment `
    -Context $SharedContext `
    -Contract $PlatformContract `
    -Toolchain $Toolchain
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $Context = New-SwawHarnessWindowsBootstrapContext `
        -DataRepo (Join-Path $TestRoot 'data.repo')
    $CoreCandidateRoots = @(
        Invoke-SwawHarnessWindowsCoreCandidateBuild `
            -Context $Context `
            -CargoPath $Plan.CargoPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    $CoreHostCandidateRoot = Invoke-SwawHarnessWindowsCoreHostCandidateBuild `
        -Context $Context `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $UserCliCandidateRoot = Invoke-SwawHarnessWindowsUserCliCandidateBuild `
        -Context $Context `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $Releases = @(Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidateRoots ([string[]]$CoreCandidateRoots) `
        -CoreHostCandidateRoot ([string]$CoreHostCandidateRoot) `
        -UserCliCandidateRoot ([string]$UserCliCandidateRoot))
    if ($Releases.Count -ne 1) {
        throw 'Skill invocation test requires one Bootstrap Release.'
    }

    $ModuleAdminRoot = Join-Path $TestRoot 'data\admin'
    [void][IO.Directory]::CreateDirectory($ModuleAdminRoot)
    Copy-Item `
        -LiteralPath (Join-Path $RepositoryRoot 'data\admin\map') `
        -Destination (Join-Path $ModuleAdminRoot 'map') `
        -Recurse
    $PublishedModules = @(Publish-SwawHarnessWindowsBootstrapModules `
        -Context $Context `
        -BootstrapRelease $Releases[0])
    if ($PublishedModules.Count -ne ($CoreContracts.Count + 1)) {
        throw 'Skill invocation fixture must publish every startup Module Release.'
    }
    $HostModuleReleases = @($PublishedModules | Where-Object {
        [string]$_.ModuleId -ceq $HostContract.ModuleId
    })
    if ($HostModuleReleases.Count -ne 1) {
        throw 'Skill invocation fixture requires one Core Host Module Release.'
    }
    $AdminHost = Initialize-SwawHarnessWindowsAdmin `
        -Context $Context `
        -BootstrapRelease $Releases[0] `
        -HostModuleRelease $HostModuleReleases[0]
    $HostVersion = [IO.File]::ReadAllText(
        [string]$AdminHost.HostVersionPointerPath,
        [Text.Encoding]::UTF8
    ).TrimEnd("`r", "`n")
    $AdminHostMembers = @(Get-ChildItem `
        -LiteralPath (Join-Path $ModuleAdminRoot 'host') `
        -Force)
    if ($HostVersion -cne $HostContract.ModuleVersion -or
        @($AdminHostMembers | Where-Object {
            [string]$_.Name -ceq 'swaw-harness-core.exe' -or
            [string]$_.Name -ceq 'manifest.json'
        }).Count -ne 0) {
        throw 'Admin Core Host version pointer layout is invalid.'
    }
    [IO.Directory]::Move(
        [string]$Context.DataRepo,
        ([string]$Context.DataRepo + '.hidden')
    )

    $PointerPath = [string]$AdminHost.HostVersionPointerPath
    [IO.File]::Delete($PointerPath)
    $MissingPointer = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('helloworld') `
        -WorkingDirectory (Join-Path $TestRoot 'data')
    if ($MissingPointer.ExitCode -ne 1 -or
        $MissingPointer.Error -cnotmatch '^\[ERROR\] Cannot connect') {
        throw 'User CLI did not reject a missing Core Host version pointer.'
    }
    [IO.File]::WriteAllText(
        $PointerPath,
        "1.*`n",
        [Text.UTF8Encoding]::new($false)
    )
    $InvalidPointer = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('helloworld') `
        -WorkingDirectory (Join-Path $TestRoot 'data')
    if ($InvalidPointer.ExitCode -ne 1 -or
        $InvalidPointer.Error -cnotmatch '^\[ERROR\] Cannot connect') {
        throw 'User CLI did not reject a non-exact Core Host version pointer.'
    }
    [IO.File]::WriteAllText(
        $PointerPath,
        "$($HostContract.ModuleVersion)`n",
        [Text.UTF8Encoding]::new($false)
    )
    $HostExecutablePath = [string]$AdminHost.HostModuleRelease.ExecutablePath
    $HiddenHostExecutablePath = "$HostExecutablePath.hidden"
    [IO.File]::Move($HostExecutablePath, $HiddenHostExecutablePath)
    try {
        $MissingHostExecutable = Invoke-SwawHarnessCapturedProcess `
            -Executable $AdminHost.UserCliPath `
            -Arguments @('helloworld') `
            -WorkingDirectory (Join-Path $TestRoot 'data')
        if ($MissingHostExecutable.ExitCode -ne 1 -or
            $MissingHostExecutable.Error -cnotmatch '^\[ERROR\] Cannot connect') {
            throw 'User CLI did not reject a missing Core Host executable.'
        }
    } finally {
        [IO.File]::Move($HiddenHostExecutablePath, $HostExecutablePath)
    }
    $ConcurrentCalls = @('Swaw', 'One', 'Two', 'Three') | ForEach-Object {
        $Info = [Diagnostics.ProcessStartInfo]::new()
        $Info.FileName = [string]$AdminHost.UserCliPath
        $Info.ArgumentList.Add('helloworld')
        $Info.ArgumentList.Add($_)
        $Info.WorkingDirectory = Join-Path $TestRoot 'data'
        $Info.UseShellExecute = $false
        $Info.CreateNoWindow = $true
        $Info.RedirectStandardOutput = $true
        $Info.RedirectStandardError = $true
        $Process = [Diagnostics.Process]::Start($Info)
        $Process | Add-Member -NotePropertyName ExpectedOutput `
            -NotePropertyValue "Hello, $_!"
        $Process | Add-Member -NotePropertyName OutputTask `
            -NotePropertyValue $Process.StandardOutput.ReadToEndAsync()
        $Process | Add-Member -NotePropertyName ErrorTask `
            -NotePropertyValue $Process.StandardError.ReadToEndAsync()
        $Process
    }
    foreach ($Process in $ConcurrentCalls) {
        if (-not $Process.WaitForExit(30000)) {
            $Process.Kill($true)
            throw 'Concurrent Admin User CLI invocation timed out.'
        }
        $Process.WaitForExit()
        if ($Process.ExitCode -ne 0 -or
            ([string]$Process.OutputTask.Result).TrimEnd("`r", "`n") -cne
                [string]$Process.ExpectedOutput -or
            -not [string]::IsNullOrEmpty([string]$Process.ErrorTask.Result)) {
            throw 'Concurrent Admin User CLI invocation returned a bad result.'
        }
        $Process.Dispose()
    }
    $FixtureHosts = @(Get-Process swaw-harness-core -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -eq $HostExecutablePath
        })
    if ($FixtureHosts.Count -ne 1) {
        throw 'Concurrent cold start did not leave exactly one Admin Core Host.'
    }
    $InvalidInvocation = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('helloworld', 'one', 'two') `
        -WorkingDirectory (Join-Path $TestRoot 'data') `
        -TimeoutSeconds 30
    if ($InvalidInvocation.ExitCode -ne 2 -or
        -not [string]::IsNullOrEmpty($InvalidInvocation.Output) -or
        $InvalidInvocation.Error -cne 'usage: helloworld [recipient]') {
        throw 'Admin User CLI did not preserve module stderr and exit code 2.'
    }

    $TestEnvironment = [ordered]@{}
    foreach ($Entry in $Plan.EnvironmentVariables.GetEnumerator()) {
        $TestEnvironment[$Entry.Key] = $Entry.Value
    }
    $TestEnvironment['SWAW_HARNESS_TEST_DATA_HOME'] = `
        (Join-Path $TestRoot 'data')
    $TestEnvironment['SWAW_HARNESS_TEST_HELLOWORLD_VERSION'] = `
        [string]$HelloworldContract.ModuleVersion
    $TestEnvironment['SWAW_HARNESS_TEST_DEV_VERSION'] = `
        [string]$DevContract.ModuleVersion
    $TestEnvironment['SWAW_HARNESS_TEST_PLATFORM_TARGET_ID'] = `
        [string]$PlatformContract.PlatformTargetId
    $WorkspaceManifest = Join-Path $RepositoryRoot 'core\Cargo.toml'
    $CargoTargetRoot = Join-Path $TestRoot 'cargo-target'
    $RustTargetConfiguration = (
        "target.$($PlatformContract.PlatformTargetId).rustflags=" +
        '["-C","target-feature=+crt-static"]'
    )
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $Plan.CargoPath `
        -Arguments @(
            '--config', $RustTargetConfiguration,
            'test',
            '--locked',
            '--manifest-path', $WorkspaceManifest,
            '--package', 'swaw-harness-core-protocol',
            '--lib',
            '--target', $PlatformContract.PlatformTargetId,
            '--target-dir', $CargoTargetRoot,
            'module_release::tests::isolated_installed_',
            '--',
            '--ignored'
        ) `
        -WorkingDirectory (Join-Path $RepositoryRoot 'core') `
        -EnvironmentVariables $TestEnvironment `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables `
        -TimeoutSeconds 1800
    if ($Result.ExitCode -ne 0) {
        throw (
            "Installed Skill invocation failed with exit code $($Result.ExitCode). " +
            "$($Result.Error) $($Result.Output)"
        ).Trim()
    }

    Write-Host '[PASS] isolated installed Skill invocation' `
        -ForegroundColor Green
} finally {
    Get-Process swaw-harness-core -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -like (Join-Path $TestRoot `
                'data\admin\modules\swaw\core\host\*\*\swaw-harness-core.exe')
        } |
        Stop-Process -Force
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}
