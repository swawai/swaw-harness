Set-StrictMode -Version 2.0

function Resolve-SwawHarnessWindowsTestDataRoot {
    param(
        [string]$DataRoot = '',
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    if ([string]::IsNullOrWhiteSpace($DataRoot)) {
        $DataRoot = Join-Path $RepositoryRoot 'data'
    }
    return [IO.Path]::GetFullPath($DataRoot)
}

function Get-SwawHarnessWindowsTestCacheRoot {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    return Join-Path `
        ([IO.Path]::GetFullPath($DataRoot)) `
        'test.windows.cache'
}

function New-SwawHarnessWindowsTestRunRoot {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    $RunsRoot = Join-Path `
        (Get-SwawHarnessWindowsTestCacheRoot -DataRoot $DataRoot) `
        'runs'
    [void][IO.Directory]::CreateDirectory($RunsRoot)
    $RunToken = [Guid]::NewGuid().ToString('N').Substring(0, 16)
    $RunRoot = Join-Path $RunsRoot $RunToken
    [void][IO.Directory]::CreateDirectory($RunRoot)
    return $RunRoot
}

function Get-SwawHarnessWindowsTestBuildRoot {
    param([Parameter(Mandatory = $true)][string]$DataRoot)

    return Join-Path `
        (Get-SwawHarnessWindowsTestCacheRoot -DataRoot $DataRoot) `
        'build'
}
