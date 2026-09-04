[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-PublicationConcurrencyTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Publication concurrency test failed: $Message"
    }
}

function New-PublicationTestCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$SetName,
        [Parameter(Mandatory = $true)][string]$ProductName,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$BuildRoot,
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$FixtureRoot
    )

    $ArtifactRoot = Join-Path $FixtureRoot "$SetName\$ProductName"
    [void][IO.Directory]::CreateDirectory($ArtifactRoot)
    $ArtifactPath = Join-Path $ArtifactRoot $Contract.ProductBinary
    [IO.File]::WriteAllBytes(
        $ArtifactPath,
        [Text.Encoding]::UTF8.GetBytes("$SetName-$ProductName")
    )
    $LifecycleLock = Enter-SwawHarnessCandidateLifecycleLock `
        -Context $Context `
        -PlatformTargetId $Contract.PlatformTargetId
    try {
        return Publish-SwawHarnessBootstrapCandidate `
            -ArtifactPath $ArtifactPath `
            -Contract $Contract `
            -BuildRoot $BuildRoot `
            -ControlledRoot $Context.BuildRoot
    } finally {
        Exit-SwawHarnessCandidateLifecycleLock -LockHandle $LifecycleLock
    }
}

function Test-PublicationReleaseEquals {
    param(
        [Parameter(Mandatory = $true)][object]$Left,
        [Parameter(Mandatory = $true)][object]$Right
    )

    return [string]$Left.ReleaseId -ceq [string]$Right.ReleaseId
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\build\candidate.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'builder\release\selector.ps1')
. (Join-Path $WindowsRoot 'core\contract.ps1')
. (Join-Path $WindowsRoot 'host\contract.ps1')
. (Join-Path $WindowsRoot 'user\contract.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
$PublicationDataRepo = Join-Path $TestRoot 'data.repo'
$FixtureRoot = Join-Path $TestRoot 'artifacts'
[void][IO.Directory]::CreateDirectory($FixtureRoot)
$RunnerPath = Join-Path $TestRoot 'invoke-publication.ps1'
$RunnerSource = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WindowsRoot,
    [Parameter(Mandatory = $true)][string]$DataRepo,
    [Parameter(Mandatory = $true)][string]$CoreHelloworldCandidateRoot,
    [Parameter(Mandatory = $true)][string]$CoreDevCandidateRoot,
    [Parameter(Mandatory = $true)][string]$CoreAdminCandidateRoot,
    [Parameter(Mandatory = $true)][string]$CoreHostCandidateRoot,
    [Parameter(Mandatory = $true)][string]$UserCliCandidateRoot,
    [Parameter(Mandatory = $true)][string]$ReadyPath,
    [Parameter(Mandatory = $true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $WindowsRoot 'publication.ps1')
$Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
[IO.File]::WriteAllText(
    $ReadyPath,
    "ready`n",
    [Text.UTF8Encoding]::new($false)
)
$Results = @(Publish-SwawHarnessWindowsProducts `
    -Context $Context `
    -CoreCandidateRoots @(
        $CoreHelloworldCandidateRoot,
        $CoreDevCandidateRoot,
        $CoreAdminCandidateRoot
    ) `
    -CoreHostCandidateRoot $CoreHostCandidateRoot `
    -UserCliCandidateRoot $UserCliCandidateRoot)
if ($Results.Count -ne 1) {
    throw 'Concurrent publication must return exactly one result.'
}
$Results[0] | Export-Clixml -LiteralPath $ResultPath
'@
[IO.File]::WriteAllText(
    $RunnerPath,
    $RunnerSource,
    [Text.UTF8Encoding]::new($false)
)

$Processes = [Collections.Generic.List[Diagnostics.Process]]::new()
$Results = [Collections.Generic.List[object]]::new()
$Gate = $null
try {
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $Context = New-SwawHarnessWindowsBootstrapContext `
        -DataRepo $PublicationDataRepo
    $CoreContracts = @(Read-SwawHarnessWindowsCoreContracts `
        -Path (Join-Path $WindowsRoot 'core\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    $CoreHostContract = Read-SwawHarnessWindowsCoreHostContract `
        -Path (Join-Path $WindowsRoot 'host\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $UserCliContract = Read-SwawHarnessWindowsUserCliContract `
        -Path (Join-Path $WindowsRoot 'user\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $Definitions = @(
        [pscustomobject]@{
            Name = 'core-helloworld'
            Contract = $CoreContracts[0]
            BuildRoot = Join-Path $Context.BuildRoot 'core'
        },
        [pscustomobject]@{
            Name = 'core-dev'
            Contract = $CoreContracts[1]
            BuildRoot = Join-Path $Context.BuildRoot 'core'
        },
        [pscustomobject]@{
            Name = 'core-admin'
            Contract = $CoreContracts[2]
            BuildRoot = Join-Path $Context.BuildRoot 'core'
        },
        [pscustomobject]@{
            Name = 'host'
            Contract = $CoreHostContract
            BuildRoot = Join-Path $Context.BuildRoot 'host'
        },
        [pscustomobject]@{
            Name = 'user'
            Contract = $UserCliContract
            BuildRoot = Join-Path $Context.BuildRoot 'user'
        }
    )
    $CandidateSets = @{}
    foreach ($SetName in @('A', 'B')) {
        $Set = @{}
        foreach ($Definition in $Definitions) {
            $Set[$Definition.Name] = New-PublicationTestCandidate `
                -SetName $SetName `
                -ProductName $Definition.Name `
                -Contract $Definition.Contract `
                -BuildRoot $Definition.BuildRoot `
                -Context $Context `
                -FixtureRoot $FixtureRoot
        }
        $CandidateSets[$SetName] = $Set
    }
    $Gate = Enter-SwawHarnessCandidateLifecycleLock `
        -Context $Context `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $HostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    foreach ($SetName in @('A', 'B')) {
        $ReadyPath = Join-Path $TestRoot "ready-$SetName.txt"
        $ResultPath = Join-Path $TestRoot "result-$SetName.clixml"
        $Info = [Diagnostics.ProcessStartInfo]::new()
        $Info.FileName = $HostPath
        $Info.Arguments = ConvertTo-SwawHarnessWindowsArguments -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', $RunnerPath,
            '-WindowsRoot', $WindowsRoot,
            '-DataRepo', $PublicationDataRepo,
            '-CoreHelloworldCandidateRoot',
                $CandidateSets[$SetName]['core-helloworld'],
            '-CoreDevCandidateRoot', $CandidateSets[$SetName]['core-dev'],
            '-CoreAdminCandidateRoot',
                $CandidateSets[$SetName]['core-admin'],
            '-CoreHostCandidateRoot', $CandidateSets[$SetName]['host'],
            '-UserCliCandidateRoot', $CandidateSets[$SetName]['user'],
            '-ReadyPath', $ReadyPath,
            '-ResultPath', $ResultPath
        )
        $Info.WorkingDirectory = $PublicationDataRepo
        $Info.UseShellExecute = $false
        $Info.CreateNoWindow = $true
        $Info.RedirectStandardOutput = $true
        $Info.RedirectStandardError = $true
        $Process = [Diagnostics.Process]::Start($Info)
        if ($null -eq $Process) {
            throw 'Could not start a concurrent publication process.'
        }
        $Process | Add-Member -NotePropertyName OutputTask `
            -NotePropertyValue $Process.StandardOutput.ReadToEndAsync()
        $Process | Add-Member -NotePropertyName ErrorTask `
            -NotePropertyValue $Process.StandardError.ReadToEndAsync()
        $Process | Add-Member -NotePropertyName ReadyPath `
            -NotePropertyValue $ReadyPath
        $Process | Add-Member -NotePropertyName ResultPath `
            -NotePropertyValue $ResultPath
        $Processes.Add($Process)
    }

    $ReadyDeadline = [DateTime]::UtcNow.AddSeconds(30)
    while (@($Processes | Where-Object {
        -not [IO.File]::Exists([string]$_.ReadyPath)
    }).Count -gt 0 -and [DateTime]::UtcNow -lt $ReadyDeadline) {
        [Threading.Thread]::Sleep(50)
    }
    Assert-PublicationConcurrencyTest `
        -Condition (@($Processes | Where-Object {
            [IO.File]::Exists([string]$_.ReadyPath)
        }).Count -eq 2) `
        -Message 'concurrent publication processes did not become ready'
    $ConsumerObserved = $false
    $ConsumerDeadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $CleanupProbe = Enter-SwawHarnessCandidateCleanupLock `
            -Context $Context `
            -PlatformTargetId $PlatformContract.PlatformTargetId
        if ($null -eq $CleanupProbe) {
            $ConsumerObserved = $true
            break
        }
        $CleanupProbe.Dispose()
        [Threading.Thread]::Sleep(50)
    } while ([DateTime]::UtcNow -lt $ConsumerDeadline)
    Assert-PublicationConcurrencyTest `
        -Condition $ConsumerObserved `
        -Message 'a waiting publisher did not register as a Candidate consumer'
    Assert-PublicationConcurrencyTest `
        -Condition (@($Processes | Where-Object { $_.HasExited }).Count -eq 0) `
        -Message 'a publication bypassed the Candidate lifecycle lock'
    Assert-PublicationConcurrencyTest `
        -Condition (-not (Test-SwawHarnessPathExists `
            -Path $Context.BootstrapReleaseRoot)) `
        -Message 'publication advanced a Release store while its gate was held'
    $CleanupRecords = @(
        Clear-SwawHarnessWindowsProductCandidates `
            -Context $Context `
            -CandidateLifecycleLock $Gate.Stream 3>&1
    )
    Assert-PublicationConcurrencyTest `
        -Condition (@($CleanupRecords | Where-Object {
            $_ -is [Management.Automation.WarningRecord]
        }).Count -ge 1) `
        -Message 'cleanup did not preserve Candidates held by active publishers'
    Exit-SwawHarnessCandidateLifecycleLock -LockHandle $Gate
    $Gate = $null

    foreach ($Process in $Processes) {
        if (-not $Process.WaitForExit(60000)) {
            Stop-SwawHarnessProcessTree -Process $Process
            throw 'Concurrent publication timed out.'
        }
        $Process.WaitForExit()
        $Output = [string]$Process.OutputTask.Result
        $ErrorText = [string]$Process.ErrorTask.Result
        if ($Process.ExitCode -ne 0) {
            throw (
                "Concurrent publication exited with $($Process.ExitCode). " +
                "$ErrorText $Output"
            ).Trim()
        }
        $Result = Import-Clixml -LiteralPath ([string]$Process.ResultPath)
        Assert-PublicationConcurrencyTest `
            -Condition (
                [string]$Result.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
                $Result.Artifacts.Count -eq 5
            ) `
            -Message 'a concurrent publication returned an incomplete set'
        $Results.Add($Result)
    }
    Assert-PublicationConcurrencyTest `
        -Condition (-not (Test-PublicationReleaseEquals `
            -Left $Results[0] `
            -Right $Results[1])) `
        -Message 'the A and B fixtures did not produce distinct Release sets'

    $Selected = Read-SwawHarnessSelectedRelease `
        -ReleasesRoot $Context.BootstrapReleaseRoot `
        -Contracts @(
            $CoreContracts
            $CoreHostContract
            $UserCliContract
        )
    Assert-PublicationConcurrencyTest `
        -Condition (
            (Test-PublicationReleaseEquals -Left $Selected -Right $Results[0]) -or
            (Test-PublicationReleaseEquals -Left $Selected -Right $Results[1])
        ) `
        -Message 'final selector does not select either complete bundle'

    $Rejected = $false
    try {
        Publish-SwawHarnessWindowsProducts `
            -Context $Context `
            -CoreCandidateRoots @(
                (Join-Path $TestRoot 'missing-candidate'),
                $CandidateSets['A']['core-dev'],
                $CandidateSets['A']['core-admin']
            ) `
            -CoreHostCandidateRoot $CandidateSets['A']['host'] `
            -UserCliCandidateRoot $CandidateSets['A']['user'] |
            Out-Null
    } catch {
        $Rejected = $true
    }
    Assert-PublicationConcurrencyTest `
        -Condition $Rejected `
        -Message 'invalid publication fixture was not rejected'
    $Probe = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "publish-bootstrap-$($PlatformContract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $Context.DataRepo `
        -TimeoutSeconds 2
    $Probe.Dispose()
    $AfterFailure = @(Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidateRoots @(
            $CandidateSets['B']['core-helloworld'],
            $CandidateSets['B']['core-dev'],
            $CandidateSets['B']['core-admin']
        ) `
        -CoreHostCandidateRoot $CandidateSets['B']['host'] `
        -UserCliCandidateRoot $CandidateSets['B']['user'])
    Assert-PublicationConcurrencyTest `
        -Condition ($AfterFailure.Count -eq 1 -and
            (Test-PublicationReleaseEquals `
                -Left $AfterFailure[0] `
                -Right $Results[1])) `
        -Message 'failed publication did not release its orchestration lock'
    Clear-SwawHarnessWindowsProductCandidates -Context $Context
    Assert-PublicationConcurrencyTest `
        -Condition (@(@('core', 'host', 'user') | Where-Object {
            Test-SwawHarnessPathExists `
                -Path (Join-Path $Context.BuildRoot "$_\candidates")
        }).Count -eq 0) `
        -Message 'released concurrent Candidates were not cleaned later'
} finally {
    if ($null -ne $Gate) {
        Exit-SwawHarnessCandidateLifecycleLock -LockHandle $Gate
    }
    foreach ($Process in $Processes) {
        if (-not $Process.HasExited) {
            Stop-SwawHarnessProcessTree -Process $Process
        }
        $Process.Dispose()
    }
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap concurrent publication' `
    -ForegroundColor Green
