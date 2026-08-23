[CmdletBinding()]
param([string]$VarRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-MainConcurrencyTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Main concurrency test failed: $Message"
    }
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot '_lib\contract.ps1')
. (Join-Path $WindowsRoot '_lib\process.ps1')
. (Join-Path $WindowsRoot '_lib\release\selector.ps1')
if ([string]::IsNullOrWhiteSpace($VarRoot)) {
    $VarRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
}
$Token = [Guid]::NewGuid().ToString('N')
$EntryA = Join-Path $VarRoot "var_entry\_test-concurrent-a-$Token"
$EntryB = Join-Path $VarRoot "var_entry\_test-concurrent-b-$Token"
$LogRoot = Join-Path $VarRoot "var_cache\_test\main-concurrency-$Token"
[void][IO.Directory]::CreateDirectory($LogRoot)
$Processes = [Collections.Generic.List[Diagnostics.Process]]::new()
try {
    $HostPath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $Index = 0
    foreach ($EntryRoot in @($EntryA, $EntryB)) {
        $Info = [Diagnostics.ProcessStartInfo]::new()
        $Info.FileName = $HostPath
        $Info.Arguments = ConvertTo-SwawHarnessWindowsArguments -Arguments @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $WindowsRoot 'main.ps1'),
            '-VarRoot', $VarRoot,
            '-EntryRoot', $EntryRoot
        )
        $Info.WorkingDirectory = $VarRoot
        $Info.UseShellExecute = $false
        $Info.CreateNoWindow = $true
        $Info.RedirectStandardOutput = $true
        $Info.RedirectStandardError = $true
        $Process = [Diagnostics.Process]::Start($Info)
        if ($null -eq $Process) {
            throw 'Could not start a concurrent Bootstrap process.'
        }
        $Process.EnableRaisingEvents = $true
        $Process | Add-Member -NotePropertyName OutputTask `
            -NotePropertyValue $Process.StandardOutput.ReadToEndAsync()
        $Process | Add-Member -NotePropertyName ErrorTask `
            -NotePropertyValue $Process.StandardError.ReadToEndAsync()
        $Processes.Add($Process)
        $Index++
    }

    foreach ($Process in $Processes) {
        if (-not $Process.WaitForExit(60000)) {
            Stop-SwawHarnessProcessTree -Process $Process
            throw 'Concurrent Bootstrap timed out.'
        }
        $Process.WaitForExit()
        $Output = [string]$Process.OutputTask.Result
        $ErrorText = [string]$Process.ErrorTask.Result
        if ($Process.ExitCode -ne 0) {
            throw (
                "Concurrent Bootstrap exited with $($Process.ExitCode). " +
                "$ErrorText $Output"
            ).Trim()
        }
    }

    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $ReleaseA = Read-SwawHarnessSelectedRelease `
        -EntryRoot $EntryA `
        -Contract $Contract
    $ReleaseB = Read-SwawHarnessSelectedRelease `
        -EntryRoot $EntryB `
        -Contract $Contract
    Assert-MainConcurrencyTest `
        -Condition (
            [string]$ReleaseA.ReleaseId -ceq [string]$ReleaseB.ReleaseId
        ) `
        -Message 'concurrent Entries did not publish the same immutable output'
} finally {
    foreach ($Process in $Processes) {
        if (-not $Process.HasExited) {
            Stop-SwawHarnessProcessTree -Process $Process
        }
        $Process.Dispose()
    }
    foreach ($Path in @($EntryA, $EntryB, $LogRoot)) {
        if ([IO.Directory]::Exists($Path)) {
            [IO.Directory]::Delete($Path, $true)
        }
    }
}

Write-Host '[PASS] Windows Bootstrap concurrent main' -ForegroundColor Green
