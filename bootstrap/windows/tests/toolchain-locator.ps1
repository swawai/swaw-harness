[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ToolchainLocatorTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Toolchain locator test failed: $Message"
    }
}

function Write-ToolchainLocatorIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ToolchainId
    )

    [void][IO.Directory]::CreateDirectory($Path)
    [IO.File]::WriteAllText(
        (Join-Path $Path 'toolchain.json'),
        (ConvertTo-SwawHarnessJsonText -Value ([ordered]@{
            toolchainId = $ToolchainId
        })),
        [Text.UTF8Encoding]::new($false)
    )
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot

    $ToolchainId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $Selection = Get-SwawHarnessToolchainTargetSelection `
        -Context $Context `
        -ToolchainId $ToolchainId
    Assert-ToolchainLocatorTest `
        -Condition ([string]$Selection.Locator -ceq 'aaaaaaa') `
        -Message 'an empty store did not choose seven hexadecimal characters'

    $CollidingId = 'aaaaaaab00000000000000000000000000000000000000000000000000000000'
    Write-ToolchainLocatorIdentity `
        -Path (Join-Path $Context.ToolchainRoot 'aaaaaaa') `
        -ToolchainId $CollidingId
    $Selection = Get-SwawHarnessToolchainTargetSelection `
        -Context $Context `
        -ToolchainId $ToolchainId
    Assert-ToolchainLocatorTest `
        -Condition ([string]$Selection.Locator -ceq 'aaaaaaaa') `
        -Message 'a complete-ID collision did not grow the locator'

    Write-ToolchainLocatorIdentity `
        -Path ([string]$Selection.Path) `
        -ToolchainId $ToolchainId
    Remove-SwawHarnessControlledPathWithRetry `
        -Path (Join-Path $Context.ToolchainRoot 'aaaaaaa') `
        -ControlledRoot $Context.DataRepo `
        -Activity 'preparing locator reuse coverage'
    $Reused = Get-SwawHarnessToolchainTargetSelection `
        -Context $Context `
        -ToolchainId $ToolchainId
    Assert-ToolchainLocatorTest `
        -Condition ([string]$Reused.Locator -ceq 'aaaaaaaa') `
        -Message 'an existing complete identity was not reused'

    $MalformedId = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
    $MalformedRoot = Join-Path $Context.ToolchainRoot 'ccccccc'
    [void][IO.Directory]::CreateDirectory($MalformedRoot)
    [IO.File]::WriteAllText(
        (Join-Path $MalformedRoot 'toolchain.json'),
        '{}',
        [Text.UTF8Encoding]::new($false)
    )
    $MalformedRejected = $false
    try {
        [void](Get-SwawHarnessToolchainTargetSelection `
            -Context $Context `
            -ToolchainId $MalformedId)
    } catch {
        $MalformedRejected = $_.Exception.Message -like (
            'Bootstrap toolchain locator has no valid complete identity*'
        )
    }
    Assert-ToolchainLocatorTest `
        -Condition $MalformedRejected `
        -Message 'malformed locator metadata was treated as an available slot'

    $ExhaustedId = 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
    for ($Length = 7; $Length -le 12; $Length++) {
        $Locator = $ExhaustedId.Substring(0, $Length)
        $OtherId = $Locator + 'e' + ('0' * (63 - $Length))
        Write-ToolchainLocatorIdentity `
            -Path (Join-Path $Context.ToolchainRoot $Locator) `
            -ToolchainId $OtherId
    }
    $ExhaustionRejected = $false
    try {
        [void](Get-SwawHarnessToolchainTargetSelection `
            -Context $Context `
            -ToolchainId $ExhaustedId)
    } catch {
        $ExhaustionRejected = $_.Exception.Message -like (
            'Bootstrap toolchain locator collision exhausted prefixes 7 through 12*'
        )
    }
    Assert-ToolchainLocatorTest `
        -Condition $ExhaustionRejected `
        -Message 'locator selection exceeded its 12-character bound'

    Write-Host '[PASS] Windows Bootstrap toolchain locator' `
        -ForegroundColor Green
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}
