Set-StrictMode -Version 2.0

function Resolve-SwawHarnessWindowsTestRepositoryDataRoot {
    param(
        [string]$RepositoryDataRoot = '',
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryDataRoot)) {
        $RepositoryDataRoot = Join-Path $RepositoryRoot 'data.repo'
    }
    return [IO.Path]::GetFullPath($RepositoryDataRoot)
}

function Get-SwawHarnessWindowsTestRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryDataRoot)

    return Join-Path `
        ([IO.Path]::GetFullPath($RepositoryDataRoot)) `
        'windows.test'
}

function New-SwawHarnessWindowsTestRunRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryDataRoot)

    $RunsRoot = Join-Path `
        (Get-SwawHarnessWindowsTestRoot -RepositoryDataRoot $RepositoryDataRoot) `
        'runs'
    [void][IO.Directory]::CreateDirectory($RunsRoot)
    $RunToken = [Guid]::NewGuid().ToString('N').Substring(0, 16)
    $RunRoot = Join-Path $RunsRoot $RunToken
    [void][IO.Directory]::CreateDirectory($RunRoot)
    return $RunRoot
}

function Get-SwawHarnessWindowsTestBuildRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryDataRoot)

    return Join-Path `
        (Get-SwawHarnessWindowsTestRoot -RepositoryDataRoot $RepositoryDataRoot) `
        'build'
}
