[CmdletBinding()]
param([string]$DataRoot = '')

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
    return Publish-SwawHarnessBootstrapCandidate `
        -ArtifactPath $ArtifactPath `
        -Contract $Contract `
        -BuildRoot $BuildRoot `
        -ControlledRoot $Context.BootstrapWindowsCacheRoot
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
. (Join-Path $WindowsRoot 'entry\contract.ps1')
. (Join-Path $WindowsRoot 'entry.manager\contract.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..\data'))
}
$DataRoot = [IO.Path]::GetFullPath($DataRoot)
[void][IO.Directory]::CreateDirectory($DataRoot)
$TestRoot = Join-Path $DataRoot (
    'bootstrap.windows.cache\_test\publication-concurrency-' +
    [Guid]::NewGuid().ToString('N')
)
$PublicationDataRoot = Join-Path $TestRoot 'data'
$FixtureRoot = Join-Path $TestRoot 'artifacts'
[void][IO.Directory]::CreateDirectory($FixtureRoot)
$RunnerPath = Join-Path $TestRoot 'invoke-publication.ps1'
$RunnerSource = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WindowsRoot,
    [Parameter(Mandatory = $true)][string]$DataRoot,
    [Parameter(Mandatory = $true)][string]$CoreCandidatePath,
    [Parameter(Mandatory = $true)][string]$EntryCandidatePath,
    [Parameter(Mandatory = $true)][string]$EntryManagerCandidatePath,
    [Parameter(Mandatory = $true)][string]$ReadyPath,
    [Parameter(Mandatory = $true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $WindowsRoot 'publication.ps1')
[IO.File]::WriteAllText(
    $ReadyPath,
    "ready`n",
    [Text.UTF8Encoding]::new($false)
)
$Results = @(Publish-SwawHarnessWindowsProducts `
    -DataRoot $DataRoot `
    -CoreCandidatePath $CoreCandidatePath `
    -EntryCandidatePath $EntryCandidatePath `
    -EntryManagerCandidatePath $EntryManagerCandidatePath)
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
        -DataRoot $PublicationDataRoot
    $CoreContract = Read-SwawHarnessWindowsCoreContract `
        -Path (Join-Path $WindowsRoot 'core\contract.json') `
        -TargetId $PlatformContract.TargetId
    $EntryContract = Read-SwawHarnessWindowsEntryContract `
        -Path (Join-Path $WindowsRoot 'entry\contract.json') `
        -TargetId $PlatformContract.TargetId
    $EntryManagerContract = Read-SwawHarnessWindowsEntryManagerContract `
        -Path (Join-Path $WindowsRoot 'entry.manager\contract.json') `
        -TargetId $PlatformContract.TargetId
    $Definitions = @(
        [pscustomobject]@{
            Name = 'core'
            Contract = $CoreContract
            BuildRoot = Join-Path $Context.BootstrapWindowsCacheRoot (
                "build\core\$($PlatformContract.TargetId)"
            )
        },
        [pscustomobject]@{
            Name = 'entry'
            Contract = $EntryContract
            BuildRoot = Join-Path $Context.BootstrapWindowsCacheRoot (
                "build\entry\$($PlatformContract.TargetId)"
            )
        },
        [pscustomobject]@{
            Name = 'entry.manager'
            Contract = $EntryManagerContract
            BuildRoot = Join-Path $Context.BootstrapWindowsCacheRoot (
                "build\entry.manager\$($PlatformContract.TargetId)"
            )
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

    $Gate = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "publish-bootstrap-$($PlatformContract.TargetId).lock"
        )) `
        -ControlledRoot $Context.BootstrapWindowsRoot `
        -TimeoutSeconds 30
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
            '-DataRoot', $PublicationDataRoot,
            '-CoreCandidatePath', $CandidateSets[$SetName]['core'],
            '-EntryCandidatePath', $CandidateSets[$SetName]['entry'],
            '-EntryManagerCandidatePath',
                $CandidateSets[$SetName]['entry.manager'],
            '-ReadyPath', $ReadyPath,
            '-ResultPath', $ResultPath
        )
        $Info.WorkingDirectory = $PublicationDataRoot
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
    [Threading.Thread]::Sleep(2000)
    Assert-PublicationConcurrencyTest `
        -Condition (@($Processes | Where-Object { $_.HasExited }).Count -eq 0) `
        -Message 'a publication bypassed the target-scoped publication lock'
    Assert-PublicationConcurrencyTest `
        -Condition (-not (Test-SwawHarnessPathExists `
            -Path $Context.BootstrapReleaseRoot)) `
        -Message 'publication advanced a Release store while its gate was held'
    $Gate.Dispose()
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
                $Result.Artifacts.Count -eq 3
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
        -Contracts @($CoreContract, $EntryContract, $EntryManagerContract)
    Assert-PublicationConcurrencyTest `
        -Condition (
            (Test-PublicationReleaseEquals -Left $Selected -Right $Results[0]) -or
            (Test-PublicationReleaseEquals -Left $Selected -Right $Results[1])
        ) `
        -Message 'final selector does not select either complete bundle'

    $Rejected = $false
    try {
        Publish-SwawHarnessWindowsProducts `
            -DataRoot $PublicationDataRoot `
            -CoreCandidatePath (Join-Path $TestRoot 'missing-candidate.json') `
            -EntryCandidatePath $CandidateSets['A']['entry'] `
            -EntryManagerCandidatePath $CandidateSets['A']['entry.manager'] |
            Out-Null
    } catch {
        $Rejected = $true
    }
    Assert-PublicationConcurrencyTest `
        -Condition $Rejected `
        -Message 'invalid publication fixture was not rejected'
    $Probe = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "publish-bootstrap-$($PlatformContract.TargetId).lock"
        )) `
        -ControlledRoot $Context.BootstrapWindowsRoot `
        -TimeoutSeconds 2
    $Probe.Dispose()
    $AfterFailure = @(Publish-SwawHarnessWindowsProducts `
        -DataRoot $PublicationDataRoot `
        -CoreCandidatePath $CandidateSets['B']['core'] `
        -EntryCandidatePath $CandidateSets['B']['entry'] `
        -EntryManagerCandidatePath $CandidateSets['B']['entry.manager'])
    Assert-PublicationConcurrencyTest `
        -Condition ($AfterFailure.Count -eq 1 -and
            (Test-PublicationReleaseEquals `
                -Left $AfterFailure[0] `
                -Right $Results[1])) `
        -Message 'failed publication did not release its orchestration lock'
} finally {
    if ($null -ne $Gate) {
        $Gate.Dispose()
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
