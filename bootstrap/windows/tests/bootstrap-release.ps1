[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-BootstrapReleaseTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Bootstrap Release test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $WindowsRoot 'core\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry.manager\candidate-build.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'pe-imports.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
$SeedFixtureRoot = Join-Path `
    (Join-Path $DataRepo 'windows.test') `
    ("sh" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
try {
    $SharedContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Contracts = @(Get-SwawHarnessWindowsProductContracts `
        -WindowsRoot $WindowsRoot `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $SharedContext `
        -Contract $PlatformContract
    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -InstallRoot $InstallRoot
    if ($null -eq $Toolchain) {
        throw 'Bootstrap Release test requires the Contract toolchain.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain

    $Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot
    $CoreCandidateRoots = @(
        Invoke-SwawHarnessWindowsCoreCandidateBuild `
            -Context $Context `
            -CargoPath $Plan.CargoPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    $EntryCandidateRoot = Invoke-SwawHarnessWindowsEntryCandidateBuild `
        -Context $Context `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryManagerCandidateRoots = @(
        Invoke-SwawHarnessWindowsEntryManagerCandidateBuild `
        -Context $Context `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )
    $CandidateRoots = @(
        [string[]]$CoreCandidateRoots
        [string]$EntryCandidateRoot
        [string]$EntryManagerCandidateRoots[0]
        [string]$EntryManagerCandidateRoots[1]
    )
    for ($Index = 0; $Index -lt $Contracts.Count; $Index++) {
        $Members = @(Get-ChildItem `
            -LiteralPath $CandidateRoots[$Index] `
            -Force)
        Assert-BootstrapReleaseTest `
            -Condition (
                $Members.Count -eq 1 -and
                -not $Members[0].PSIsContainer -and
                [string]$Members[0].Name -ceq
                    [string]$Contracts[$Index].ProductBinary
            ) `
            -Message 'Candidate does not contain exactly one product binary'
    }

    $Arguments = @{
        Context = $Context
        CoreCandidateRoots = [string[]]$CoreCandidateRoots
        EntryCandidateRoot = [string]$EntryCandidateRoot
        EntryManagerCandidateRoots = $EntryManagerCandidateRoots
    }
    $First = Publish-SwawHarnessWindowsProducts @Arguments
    $FirstCreated = (Get-Item -LiteralPath $First.Root).CreationTimeUtc
    $Second = Publish-SwawHarnessWindowsProducts @Arguments
    $Selected = Read-SwawHarnessSelectedRelease `
        -ReleasesRoot $Context.BootstrapReleaseRoot `
        -Contracts $Contracts

    $ReleaseDirectories = @(
        Get-ChildItem -LiteralPath $Context.BootstrapReleaseRoot `
            -Directory -Force
    )
    $ExpectedNames = @($Contracts | ForEach-Object { $_.ProductBinary })
    $ActualNames = @($Selected.Artifacts | ForEach-Object { $_.Name })
    Assert-BootstrapReleaseTest `
        -Condition (
            [string]$First.ReleaseId -ceq [string]$Second.ReleaseId -and
            [string]$Selected.ReleaseId -ceq [string]$First.ReleaseId -and
            $ReleaseDirectories.Count -eq 1 -and
            (Get-Item -LiteralPath $Second.Root).CreationTimeUtc -eq
                $FirstCreated -and
            $Selected.Artifacts.Count -eq $Contracts.Count -and
            [string]::Join('|', $ActualNames) -ceq
                [string]::Join('|', $ExpectedNames)
        ) `
        -Message 'bundle publication is not complete, immutable, and idempotent'
    $Selector = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-BootstrapReleaseTest `
        -Condition ($Selector -ceq [string]$First.ReleaseId) `
        -Message 'the target selector does not select the bundle Release'

    $IncompleteManagerRejected = $false
    try {
        [void](Publish-SwawHarnessWindowsProducts `
            -Context $Context `
            -CoreCandidateRoots ([string[]]$CoreCandidateRoots) `
            -EntryCandidateRoot ([string]$EntryCandidateRoot) `
            -EntryManagerCandidateRoots @(
                [string]$EntryManagerCandidateRoots[0]
            ))
    } catch {
        $IncompleteManagerRejected = $true
    }
    Assert-BootstrapReleaseTest `
        -Condition $IncompleteManagerRejected `
        -Message 'bundle publication accepted only one Entry Manager frontend'

    foreach ($Artifact in $Selected.Artifacts) {
        [void](Assert-SwawHarnessNoExternalCrtImports `
            -ArtifactPath $Artifact.Path `
            -LinkerPath $Plan.LinkerPath `
            -EnvironmentVariables $Plan.EnvironmentVariables `
            -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables)
    }
    $CoreArtifact = @($Selected.Artifacts | Where-Object {
        $_.Name -ceq 'helloworld.exe'
    })[0]
    $Output = & $CoreArtifact.Path 'Bootstrap'
    Assert-BootstrapReleaseTest `
        -Condition (
            $LASTEXITCODE -eq 0 -and
            [string]$Output -ceq 'Hello, Bootstrap!'
        ) `
        -Message 'the bundled Core executable did not run correctly'
    $DevArtifact = @($Selected.Artifacts | Where-Object {
        $_.Name -ceq 'swaw-harness-dev.exe'
    })[0]
    $DevEntryRoot = Join-Path $TestRoot 'dev-entry'
    [void][IO.Directory]::CreateDirectory($DevEntryRoot)
    $DevResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $DevArtifact.Path `
        -Arguments @('dev/bun/mode', 'managed') `
        -WorkingDirectory $Selected.Root `
        -EnvironmentVariables @{
            SWAW_HARNESS_ENTRY_ROOT = $DevEntryRoot
        }
    $DevDocument = Join-Path `
        $DevEntryRoot `
        'export\dev\bun\mode\mode.json'
    Assert-BootstrapReleaseTest `
        -Condition (
            $DevResult.ExitCode -eq 0 -and
            $DevResult.Output -ceq 'managed' -and
            [IO.File]::Exists($DevDocument) -and
            [IO.File]::ReadAllText($DevDocument).Contains(
                '"mode": "managed"'
            )
        ) `
        -Message 'the bundled Dev executable did not persist Bun mode'

    if ($SeedFixtureRoot.Length -gt 58) {
        throw "Admin seed fixture exceeds the HarnessRoot path budget: $SeedFixtureRoot"
    }
    [void][IO.Directory]::CreateDirectory($SeedFixtureRoot)
    $CopiedReleasesRoot = Join-Path $SeedFixtureRoot 'source'
    [void][IO.Directory]::CreateDirectory($CopiedReleasesRoot)
    $CopiedReleaseRoot = Join-Path $CopiedReleasesRoot $First.ReleaseId
    Copy-Item `
        -LiteralPath $First.Root `
        -Destination $CopiedReleaseRoot `
        -Recurse `
        -Force
    $SeedHarnessRoot = Join-Path $SeedFixtureRoot 'h'
    $CopiedAdmin = Join-Path $CopiedReleaseRoot 'swaw-harness-admin.exe'
    $SeedResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $CopiedAdmin `
        -Arguments @(
            'admin/entry/swaw-harness',
            'seed',
            $SeedHarnessRoot
        ) `
        -WorkingDirectory $CopiedReleaseRoot
    $EntryRecordPath = Join-Path `
        $SeedHarnessRoot `
        'data\swaw-harness\entry.json'
    $EntryRecord = Read-SwawHarnessJsonFile `
        -Path $EntryRecordPath `
        -Description 'seeded Admin Entry record'
    Assert-SwawHarnessObjectFields `
        -Value $EntryRecord `
        -Expected @('schema', 'entryId', 'lifecycle') `
        -Description 'seeded Admin Entry record'
    $RuntimeRoot = Join-Path $SeedHarnessRoot 'data\swaw-harness\runtime'
    $RuntimeRelease = Read-SwawHarnessSelectedRelease `
        -ReleasesRoot $RuntimeRoot `
        -Contracts $Contracts
    Assert-BootstrapReleaseTest `
        -Condition (
            $SeedResult.ExitCode -eq 0 -and
            [string]$EntryRecord.schema -ceq 'swaw.harness.entry/v1' -and
            [string]$EntryRecord.entryId -ceq 'swaw-harness' -and
            [string]$EntryRecord.lifecycle -ceq 'active' -and
            [string]$RuntimeRelease.ReleaseId -ceq [string]$First.ReleaseId
        ) `
        -Message 'Admin executable did not seed one exact active Runtime Release'

    $CopiedEntry = Join-Path $CopiedReleaseRoot 'entry.exe'
    $InstalledEntry = Join-Path $RuntimeRelease.Root 'entry.exe'
    $InstalledEntryHash = Get-SwawHarnessFileSha256 -Path $InstalledEntry
    $CopiedEntryBytes = [IO.File]::ReadAllBytes($CopiedEntry)
    $CopiedEntryBytes[0] = $CopiedEntryBytes[0] -bxor 0xff
    [IO.File]::WriteAllBytes($CopiedEntry, $CopiedEntryBytes)
    Assert-BootstrapReleaseTest `
        -Condition (
            (Get-SwawHarnessFileSha256 -Path $InstalledEntry) -ceq
                $InstalledEntryHash
        ) `
        -Message 'seeded Runtime Release was hard-linked to its source Release'
    [IO.Directory]::Delete($CopiedReleasesRoot, $true)

    $InstalledAdmin = Join-Path `
        $RuntimeRelease.Root `
        'swaw-harness-admin.exe'
    $IdempotentResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $InstalledAdmin `
        -Arguments @(
            'admin/entry/swaw-harness',
            'seed',
            $SeedHarnessRoot
        ) `
        -WorkingDirectory $RuntimeRelease.Root
    Assert-BootstrapReleaseTest `
        -Condition (
            $IdempotentResult.ExitCode -eq 0 -and
            $IdempotentResult.Output -match 'already active'
        ) `
        -Message 'installed Admin module depended on its hidden source Release'

    $CoreCandidateArtifact = Join-Path `
        $CoreCandidateRoots[0] `
        $Contracts[0].ProductBinary
    $CandidateBytes = [IO.File]::ReadAllBytes($CoreCandidateArtifact)
    $CandidateBytes[0] = $CandidateBytes[0] -bxor 0xff
    [IO.File]::WriteAllBytes($CoreCandidateArtifact, $CandidateBytes)
    $Rejected = $false
    try {
        [void](Publish-SwawHarnessWindowsProducts @Arguments)
    } catch {
        $Rejected = $true
    }
    Assert-BootstrapReleaseTest `
        -Condition $Rejected `
        -Message 'bundle publication accepted a tampered Candidate'
    $SelectorAfterFailure = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    ).Trim()
    Assert-BootstrapReleaseTest `
        -Condition ($SelectorAfterFailure -ceq [string]$First.ReleaseId) `
        -Message 'failed bundle publication changed the selector'

    $EntryContractIndex = $CoreCandidateRoots.Count
    $LockedCandidateArtifact = Join-Path `
        $EntryCandidateRoot `
        $Contracts[$EntryContractIndex].ProductBinary
    $LockedCandidateStream = [IO.File]::Open(
        $LockedCandidateArtifact,
        [IO.FileMode]::Open,
        [IO.FileAccess]::Read,
        [IO.FileShare]::None
    )
    try {
        $CleanupRecords = @(
            Clear-SwawHarnessWindowsProductCandidates -Context $Context 3>&1
        )
    } finally {
        $LockedCandidateStream.Dispose()
    }
    $CleanupWarnings = @($CleanupRecords | Where-Object {
        $_ -is [Management.Automation.WarningRecord]
    })
    Assert-BootstrapReleaseTest `
        -Condition (
            $CleanupWarnings.Count -ge 1 -and
            [IO.Directory]::Exists([string]$EntryCandidateRoot)
        ) `
        -Message 'Candidate cleanup failure was not reported as a warning'

    Clear-SwawHarnessWindowsProductCandidates -Context $Context
    $RemainingCandidateRoots = @($CandidateRoots | Where-Object {
        Test-SwawHarnessPathExists -Path $_
    })
    Assert-BootstrapReleaseTest `
        -Condition ($RemainingCandidateRoots.Count -eq 0) `
        -Message 'a later Candidate cleanup did not remove stale members'
} finally {
    if ([IO.Directory]::Exists($SeedFixtureRoot)) {
        [IO.Directory]::Delete($SeedFixtureRoot, $true)
    }
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap bundle Release' -ForegroundColor Green
