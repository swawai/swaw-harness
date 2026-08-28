[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'toolchain\install-store.ps1')

function Assert-InstallPublishTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Install publish test failed: $Message"
    }
}

function New-InstallPublishFixture {
    param([string]$Path, [string]$Content)

    [void][IO.Directory]::CreateDirectory($Path)
    [IO.File]::WriteAllText(
        (Join-Path $Path 'receipt.txt'),
        $Content,
        [Text.UTF8Encoding]::new($false)
    )
}

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$DataRoot = Resolve-SwawHarnessWindowsTestDataRoot `
    -DataRoot $DataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot `
    -DataRoot $DataRoot `
    -Name 'install-publish'
try {
    $ValidateGood = {
        param($Root)

        $Receipt = Join-Path $Root 'receipt.txt'
        return [IO.File]::Exists($Receipt) -and
            [IO.File]::ReadAllText($Receipt) -ceq 'good'
    }

    $Target = Join-Path $TestRoot 'object-a'
    $Stage = Join-Path $TestRoot 'stage-a'
    New-InstallPublishFixture -Path $Stage -Content 'good'
    Publish-SwawHarnessInstallDirectory `
        -StagedPath $Stage `
        -TargetPath $Target `
        -ControlledRoot $TestRoot `
        -Name 'fixture' `
        -Validate $ValidateGood
    Assert-InstallPublishTest `
        -Condition (
            [IO.Directory]::Exists($Target) -and
            -not [IO.Directory]::Exists($Stage)
        ) `
        -Message 'validated stage was not moved to an absent target'

    $SecondStage = Join-Path $TestRoot 'stage-b'
    New-InstallPublishFixture -Path $SecondStage -Content 'good'
    $ExistingRejected = $false
    try {
        Publish-SwawHarnessInstallDirectory `
            -StagedPath $SecondStage `
            -TargetPath $Target `
            -ControlledRoot $TestRoot `
            -Name 'fixture' `
            -Validate $ValidateGood
    } catch {
        $ExistingRejected = $_.Exception.Message -like '*already exists*'
    }
    Assert-InstallPublishTest `
        -Condition (
            $ExistingRejected -and
            [IO.File]::ReadAllText((Join-Path $Target 'receipt.txt')) -ceq
                'good' -and
            -not [IO.Directory]::Exists($SecondStage)
        ) `
        -Message 'existing content-addressed target was replaced or stage leaked'

    $FailedTarget = Join-Path $TestRoot 'object-b'
    $FailedStage = Join-Path $TestRoot 'stage-c'
    New-InstallPublishFixture -Path $FailedStage -Content 'good'
    $RejectTarget = {
        param($Root)

        if ([IO.Path]::GetFileName($Root) -ceq 'object-b') {
            return $false
        }
        return & $ValidateGood $Root
    }
    $PostValidationRejected = $false
    try {
        Publish-SwawHarnessInstallDirectory `
            -StagedPath $FailedStage `
            -TargetPath $FailedTarget `
            -ControlledRoot $TestRoot `
            -Name 'fixture' `
            -Validate $RejectTarget
    } catch {
        $PostValidationRejected = $true
    }
    Assert-InstallPublishTest `
        -Condition (
            $PostValidationRejected -and
            -not (Test-SwawHarnessPathExists -Path $FailedTarget) -and
            -not (Test-SwawHarnessPathExists -Path $FailedStage)
        ) `
        -Message 'failed publication left a target or stage behind'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap forward-only install publish' `
    -ForegroundColor Green
