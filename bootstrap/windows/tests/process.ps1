[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ProcessTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Process test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $WindowsRoot 'builder\process.ps1')
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRoot = Resolve-SwawHarnessWindowsTestDataRoot `
    -DataRoot $DataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot `
    -DataRoot $DataRoot `
    -Name 'process'

try {
    [void][IO.Directory]::CreateDirectory($TestRoot)
    $PowerShell = Join-Path $env:SystemRoot (
        'System32\WindowsPowerShell\v1.0\powershell.exe'
    )
    $ArgumentProbe = Join-Path $TestRoot 'argv.ps1'
    [IO.File]::WriteAllText(
        $ArgumentProbe,
        '[Console]::Write([string]::Join(''|'', [string[]]$args))',
        [Text.UTF8Encoding]::new($false)
    )
    $ArgumentResult = Invoke-SwawHarnessCapturedProcess `
        -Executable $PowerShell `
        -Arguments @(
            '-NoLogo', '-NoProfile', '-File',
            $ArgumentProbe,
            'alpha',
            'space value',
            'quote"value',
            'trail\',
            ''
        ) `
        -WorkingDirectory $TestRoot
    Assert-ProcessTest `
        -Condition ($ArgumentResult.ExitCode -eq 0 -and
            $ArgumentResult.Output -ceq
                'alpha|space value|quote"value|trail\|') `
        -Message 'Windows native argument encoding changed an argument'

    $Marker = Join-Path $TestRoot 'child-survived.txt'
    $ParentScript = Join-Path $TestRoot 'parent.ps1'
    $ChildScript = Join-Path $TestRoot 'child.ps1'
    [IO.File]::WriteAllText(
        $ChildScript,
        'param([string]$Marker) Start-Sleep -Seconds 3; ' +
            '[IO.File]::WriteAllText($Marker, ''survived'')',
        [Text.UTF8Encoding]::new($false)
    )
    $ParentContent = @'
param([string]$Marker, [string]$ChildScript)
Start-Sleep -Milliseconds 500
$argumentText = '-NoLogo -NoProfile -File "' + $ChildScript + '" "' + $Marker + '"'
$child = Start-Process `
    -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList $argumentText `
    -WindowStyle Hidden `
    -PassThru
$child.WaitForExit()
'@
    [IO.File]::WriteAllText(
        $ParentScript,
        $ParentContent,
        [Text.UTF8Encoding]::new($false)
    )
    $TimedOut = $false
    try {
        [void](Invoke-SwawHarnessCapturedProcess `
            -Executable $PowerShell `
            -Arguments @(
                '-NoLogo', '-NoProfile', '-File', $ParentScript,
                $Marker, $ChildScript
            ) `
            -WorkingDirectory $TestRoot `
            -TimeoutSeconds 1)
    } catch {
        $TimedOut = $_.Exception.Message -like '*timed out*'
    }
    Start-Sleep -Seconds 4
    Assert-ProcessTest `
        -Condition ($TimedOut -and -not [IO.File]::Exists($Marker)) `
        -Message 'timed-out process left a descendant running'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap process isolation' -ForegroundColor Green
