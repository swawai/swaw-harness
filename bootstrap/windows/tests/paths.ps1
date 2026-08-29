Set-StrictMode -Version 2.0

function Resolve-SwawHarnessWindowsTestDataRepo {
    param(
        [string]$DataRepo = '',
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    if ([string]::IsNullOrWhiteSpace($DataRepo)) {
        $DataRepo = Join-Path $RepositoryRoot 'data.repo'
    }
    return [IO.Path]::GetFullPath($DataRepo)
}

function Get-SwawHarnessWindowsTestRoot {
    param([Parameter(Mandatory = $true)][string]$DataRepo)

    return Join-Path `
        ([IO.Path]::GetFullPath($DataRepo)) `
        'windows.test'
}

function New-SwawHarnessWindowsTestRunRoot {
    param([Parameter(Mandatory = $true)][string]$DataRepo)

    $RunsRoot = Join-Path `
        (Get-SwawHarnessWindowsTestRoot -DataRepo $DataRepo) `
        'runs'
    [void][IO.Directory]::CreateDirectory($RunsRoot)
    $RunToken = [Guid]::NewGuid().ToString('N').Substring(0, 16)
    $RunRoot = Join-Path $RunsRoot $RunToken
    [void][IO.Directory]::CreateDirectory($RunRoot)
    return $RunRoot
}

function Get-SwawHarnessWindowsTestBuildRoot {
    param([Parameter(Mandatory = $true)][string]$DataRepo)

    return Join-Path `
        (Get-SwawHarnessWindowsTestRoot -DataRepo $DataRepo) `
        'build'
}
