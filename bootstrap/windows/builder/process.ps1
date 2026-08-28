Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'path-budget.ps1')

function ConvertTo-SwawHarnessWindowsArgument {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }
    $Builder = [Text.StringBuilder]::new()
    [void]$Builder.Append('"')
    $Backslashes = 0
    foreach ($Character in $Value.ToCharArray()) {
        if ($Character -eq [char]'\') {
            $Backslashes++
            continue
        }
        if ($Character -eq [char]'"') {
            [void]$Builder.Append([char]'\', $Backslashes * 2 + 1)
            [void]$Builder.Append('"')
            $Backslashes = 0
            continue
        }
        if ($Backslashes -gt 0) {
            [void]$Builder.Append([char]'\', $Backslashes)
            $Backslashes = 0
        }
        [void]$Builder.Append($Character)
    }
    if ($Backslashes -gt 0) {
        [void]$Builder.Append([char]'\', $Backslashes * 2)
    }
    [void]$Builder.Append('"')
    return $Builder.ToString()
}

function ConvertTo-SwawHarnessWindowsArguments {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments
    )

    $Encoded = foreach ($Argument in $Arguments) {
        ConvertTo-SwawHarnessWindowsArgument -Value ([string]$Argument)
    }
    return [string]::Join(' ', [string[]]@($Encoded))
}

function Stop-SwawHarnessProcessTree {
    param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)

    if ($Process.HasExited) {
        return
    }
    $Taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if ([IO.File]::Exists($Taskkill)) {
        try {
            $Info = [Diagnostics.ProcessStartInfo]::new()
            $Info.FileName = $Taskkill
            $Info.Arguments = "/pid $($Process.Id) /t /f"
            $Info.UseShellExecute = $false
            $Info.CreateNoWindow = $true
            $Killer = [Diagnostics.Process]::Start($Info)
            if ($null -ne $Killer) {
                try {
                    [void]$Killer.WaitForExit(10000)
                } finally {
                    $Killer.Dispose()
                }
            }
        } catch {}
    }
    if (-not $Process.HasExited) {
        try { $Process.Kill() } catch {}
    }
    try { [void]$Process.WaitForExit(5000) } catch {}
}

function Invoke-SwawHarnessCapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @(),
        [int]$TimeoutSeconds = 120
    )

    if ($TimeoutSeconds -le 0) {
        throw 'Process timeout must be positive.'
    }
    Assert-SwawHarnessExternalProcessPathBudget `
        -Executable $Executable `
        -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -EnvironmentVariables $EnvironmentVariables
    $Info = [Diagnostics.ProcessStartInfo]::new()
    $Info.FileName = $Executable
    $Info.Arguments = ConvertTo-SwawHarnessWindowsArguments `
        -Arguments $Arguments
    $Info.WorkingDirectory = $WorkingDirectory
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $true
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $null = $Info.EnvironmentVariables
    foreach ($Name in $UnsetEnvironmentVariables) {
        if ($Info.EnvironmentVariables.ContainsKey($Name)) {
            $Info.EnvironmentVariables.Remove($Name)
        }
    }
    foreach ($Name in $EnvironmentVariables.Keys) {
        $Info.EnvironmentVariables[[string]$Name] =
            [string]$EnvironmentVariables[$Name]
    }

    $Process = [Diagnostics.Process]::Start($Info)
    if ($null -eq $Process) {
        throw "Failed to start process: $Executable"
    }
    try {
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-SwawHarnessProcessTree -Process $Process
            throw "Process timed out after $TimeoutSeconds seconds: $Executable"
        }
        $Process.WaitForExit()
        return [pscustomobject][ordered]@{
            ExitCode = [int]$Process.ExitCode
            Output = ([string]$OutputTask.Result).Trim()
            Error = ([string]$ErrorTask.Result).Trim()
        }
    } finally {
        $Process.Dispose()
    }
}

function Invoke-SwawHarnessInheritedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @(),
        [int]$TimeoutSeconds = 1800
    )

    if ($TimeoutSeconds -le 0) {
        throw 'Process timeout must be positive.'
    }
    Assert-SwawHarnessExternalProcessPathBudget `
        -Executable $Executable `
        -Arguments $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -EnvironmentVariables $EnvironmentVariables
    $Info = [Diagnostics.ProcessStartInfo]::new()
    $Info.FileName = $Executable
    $Info.Arguments = ConvertTo-SwawHarnessWindowsArguments `
        -Arguments $Arguments
    $Info.WorkingDirectory = $WorkingDirectory
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $false
    $null = $Info.EnvironmentVariables
    foreach ($Name in $UnsetEnvironmentVariables) {
        if ($Info.EnvironmentVariables.ContainsKey($Name)) {
            $Info.EnvironmentVariables.Remove($Name)
        }
    }
    foreach ($Name in $EnvironmentVariables.Keys) {
        $Info.EnvironmentVariables[[string]$Name] =
            [string]$EnvironmentVariables[$Name]
    }

    $Process = [Diagnostics.Process]::Start($Info)
    if ($null -eq $Process) {
        throw "Failed to start process: $Executable"
    }
    try {
        if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-SwawHarnessProcessTree -Process $Process
            throw "Process timed out after $TimeoutSeconds seconds: $Executable"
        }
        return [int]$Process.ExitCode
    } finally {
        $Process.Dispose()
    }
}
