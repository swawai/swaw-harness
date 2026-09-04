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
. (Join-Path $PSScriptRoot 'harness-user.ps1')
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
$AdminContracts = @($CoreContracts | Where-Object {
    $_.ModuleId -ceq 'swaw/core/admin'
})
if ($HelloworldContracts.Count -ne 1 -or $DevContracts.Count -ne 1 -or
    $AdminContracts.Count -ne 1) {
    throw 'Skill invocation test requires Helloworld, Dev, and Admin contracts.'
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
    $UserCliArtifacts = @($Releases[0].Artifacts | Where-Object {
        [string]$_.Name -ceq 'user.exe'
    })
    if ($UserCliArtifacts.Count -ne 1) {
        throw 'Skill invocation fixture requires one User CLI executable.'
    }
    [IO.File]::WriteAllBytes(
        [string]$AdminHost.UserCliPath,
        [byte[]]@(0)
    )
    $AdminHost = Initialize-SwawHarnessWindowsAdmin `
        -Context $Context `
        -BootstrapRelease $Releases[0] `
        -HostModuleRelease $HostModuleReleases[0]
    $PublishedUserCli = Get-Item -LiteralPath $AdminHost.UserCliPath -Force
    $AdminPublicationResidues = @(Get-ChildItem `
        -LiteralPath (Join-Path $TestRoot 'data') `
        -Force | Where-Object {
            [string]$_.Name -cmatch '^\.admin-[a-f0-9]{32}\.tmp(?:\.backup)?$'
        })
    if ([long]$PublishedUserCli.Length -ne
            [long]$UserCliArtifacts[0].Length -or
        (Get-SwawHarnessFileSha256 -Path $AdminHost.UserCliPath) -cne
            [string]$UserCliArtifacts[0].Sha256 -or
        $AdminPublicationResidues.Count -ne 0) {
        throw 'Admin User CLI executable replacement was not atomic and complete.'
    }
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
        -Arguments @('core/helloworld') `
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
        -Arguments @('core/helloworld') `
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
            -Arguments @('core/helloworld') `
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
        $Info.Arguments = "core/helloworld $_"
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
            $Process.Kill()
            throw 'Concurrent Admin User CLI invocation timed out.'
        }
        $Process.WaitForExit()
        $ErrorText = ([string]$Process.ErrorTask.Result).Trim()
        $RunMatch = [regex]::Match(
            $ErrorText,
            '^\[RUN\] (?<id>[a-f0-9]{32})$'
        )
        if ($Process.ExitCode -ne 0 -or
            ([string]$Process.OutputTask.Result).TrimEnd("`r", "`n") -cne
                [string]$Process.ExpectedOutput -or
            -not $RunMatch.Success) {
            throw 'Concurrent Admin User CLI invocation returned a bad result.'
        }
        $Process | Add-Member -NotePropertyName RunId `
            -NotePropertyValue $RunMatch.Groups['id'].Value
        $Process.Dispose()
    }
    $AdminRunsRoot = Join-Path $ModuleAdminRoot 'runs'
    $ConcurrentRuns = @(Get-ChildItem `
        -LiteralPath $AdminRunsRoot `
        -Directory `
        -Force)
    $ReturnedRunIds = @($ConcurrentCalls | ForEach-Object {
        [string]$_.RunId
    })
    if ($ConcurrentRuns.Count -ne $ConcurrentCalls.Count -or
        @($ReturnedRunIds | Select-Object -Unique).Count -ne
            $ConcurrentCalls.Count) {
        throw 'Concurrent Skill invocations did not create one Run per call.'
    }
    foreach ($Run in $ConcurrentRuns) {
        $RunRecordPath = Join-Path $Run.FullName 'run.json'
        $RunNodePath = Join-Path $Run.FullName 'core\helloworld'
        $RunRecord = Get-Content `
            -LiteralPath $RunRecordPath `
            -Raw | ConvertFrom-Json
        if ([string]$Run.Name -cnotmatch '^[a-f0-9]{32}$' -or
            [string]$RunRecord.schema -cne 'swaw.harness.run/v1' -or
            [string]$RunRecord.runId -cne [string]$Run.Name -or
            [string]$RunRecord.target.skillMapId -cne 'core' -or
            [string]$RunRecord.target.skillPath -cne 'helloworld' -or
            [string]$RunRecord.target.method -cne 'node' -or
            [string]$RunRecord.moduleRelease.module -cne
                'swaw/templates/helloworld' -or
            [string]$RunRecord.moduleRelease.version -cne
                [string]$HelloworldContract.ModuleVersion -or
            [string]$RunRecord.result.state -cne 'completed' -or
            [int]$RunRecord.result.exitCode -ne 0 -or
            @($RunRecord.argumentsUtf16).Count -ne 1 -or
            -not [IO.Directory]::Exists($RunNodePath) -or
            $ReturnedRunIds -cnotcontains [string]$Run.Name) {
            throw "Run record or node working directory is invalid: $($Run.FullName)"
        }
    }
    $FixtureHosts = @(Get-Process swaw-harness-core -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Path -eq $HostExecutablePath
        })
    if ($FixtureHosts.Count -ne 1) {
        throw 'Concurrent cold start did not leave exactly one Admin Core Host.'
    }
    $ReservedTreeInvocation = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('core/helloworld/.tree') `
        -WorkingDirectory (Join-Path $TestRoot 'data') `
        -TimeoutSeconds 30
    $RunsAfterReservedTree = @(Get-ChildItem `
        -LiteralPath $AdminRunsRoot `
        -Directory `
        -Force)
    if ($ReservedTreeInvocation.ExitCode -ne 1 -or
        -not [string]::IsNullOrEmpty($ReservedTreeInvocation.Output) -or
        $ReservedTreeInvocation.Error -cne
            "[ERROR] Core Host node method '/.tree' is not implemented" -or
        $RunsAfterReservedTree.Count -ne $ConcurrentRuns.Count) {
        throw 'Reserved tree method was not rejected before creating a Run.'
    }
    $InvalidInvocation = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('core/helloworld', 'one', 'two') `
        -WorkingDirectory (Join-Path $TestRoot 'data') `
        -TimeoutSeconds 30
    $InvalidRunMatch = [regex]::Match(
        $InvalidInvocation.Error,
        '^\[RUN\] (?<id>[a-f0-9]{32})\r?\nusage: helloworld \[recipient\]$'
    )
    if ($InvalidInvocation.ExitCode -ne 2 -or
        -not [string]::IsNullOrEmpty($InvalidInvocation.Output) -or
        -not $InvalidRunMatch.Success) {
        throw 'Admin User CLI did not preserve module stderr and exit code 2.'
    }
    $CompletedRuns = @(Get-ChildItem `
        -LiteralPath $AdminRunsRoot `
        -Directory `
        -Force | ForEach-Object {
            Get-Content `
                -LiteralPath (Join-Path $_.FullName 'run.json') `
                -Raw | ConvertFrom-Json
        })
    if ($CompletedRuns.Count -ne ($ConcurrentCalls.Count + 1) -or
        @($CompletedRuns | Where-Object {
            [string]$_.result.state -ceq 'completed' -and
            [int]$_.result.exitCode -eq 2 -and
            [string]$_.runId -ceq $InvalidRunMatch.Groups['id'].Value
        }).Count -ne 1) {
        throw 'Nonzero module exit was not preserved in its Run record.'
    }

    Test-SwawHarnessUserCreation `
        -TestRoot $TestRoot `
        -ModuleAdminRoot $ModuleAdminRoot `
        -AdminHost $AdminHost `
        -PlatformTargetId $PlatformContract.PlatformTargetId `
        -HostModuleVersion $HostContract.ModuleVersion

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
