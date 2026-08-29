[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-MainTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Main test failed: $Message"
    }
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($DataRepo)) {
    $DataRepo = [IO.Path]::GetFullPath((
        Join-Path $WindowsRoot '..\..\data.repo'
    ))
}
$FirstResults = @(& (Join-Path $WindowsRoot 'main.ps1'))
Assert-MainTest `
    -Condition ($FirstResults.Count -eq 1) `
    -Message 'first invocation did not return exactly one Bootstrap Release'
$First = $FirstResults[0]
$FirstCandidateMembers = @(
    foreach ($Product in @('core', 'entry', 'manager')) {
        $CandidatesRoot = Join-Path `
            $DataRepo `
            "windows.build\$Product\candidates"
        if ([IO.Directory]::Exists($CandidatesRoot)) {
            Get-ChildItem -LiteralPath $CandidatesRoot -Force
        }
    }
)
$ExpectedReleaseRoot = [IO.Path]::GetFullPath(
    (Join-Path $DataRepo 'windows.release')
)
Assert-MainTest `
    -Condition (
        (Split-Path -Path ([string]$First.Root) -Parent).Equals(
            $ExpectedReleaseRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $First.Artifacts.Count -eq 4 -and
        $FirstCandidateMembers.Count -eq 0
    ) `
    -Message 'main did not publish one complete Bootstrap Release'

$SecondInvocation = @(
    & (Join-Path $WindowsRoot 'main.ps1') 6>&1
)
$SecondResults = @($SecondInvocation | Where-Object {
    $_ -isnot [Management.Automation.InformationRecord]
})
$SecondMessages = @($SecondInvocation | Where-Object {
    $_ -is [Management.Automation.InformationRecord]
} | ForEach-Object { [string]$_.MessageData })
Assert-MainTest `
    -Condition ($SecondResults.Count -eq 1) `
    -Message 'second invocation did not return exactly one Bootstrap Release'
$Second = $SecondResults[0]
$SecondCandidateMembers = @(
    foreach ($Product in @('core', 'entry', 'manager')) {
        $CandidatesRoot = Join-Path `
            $DataRepo `
            "windows.build\$Product\candidates"
        if ([IO.Directory]::Exists($CandidatesRoot)) {
            Get-ChildItem -LiteralPath $CandidatesRoot -Force
        }
    }
)
Assert-MainTest `
    -Condition (
        [string]$First.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
        [string]$Second.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
        @($SecondMessages | Where-Object {
            $_ -cmatch '^\[BUILT\] '
        }).Count -eq 4 -and
        @($SecondMessages | Where-Object {
            $_ -cmatch '^\[PUBLISHED\] Bootstrap Release '
        }).Count -eq 1 -and
        (Split-Path -Path ([string]$Second.Root) -Parent).Equals(
            $ExpectedReleaseRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        $Second.Artifacts.Count -eq 4 -and
        @($First.Artifacts | Where-Object {
            (Get-Item -LiteralPath $_.Path).Length -gt 0
        }).Count -eq 4 -and
        @($Second.Artifacts | Where-Object {
            (Get-Item -LiteralPath $_.Path).Length -gt 0
        }).Count -eq 4 -and
        $SecondCandidateMembers.Count -eq 0
    ) `
    -Message 'explicit Bootstrap did not preserve a valid bundle Release'

Write-Host '[PASS] Windows Bootstrap main end-to-end' -ForegroundColor Green
