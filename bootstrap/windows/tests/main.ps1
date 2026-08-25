[CmdletBinding()]
param([string]$DataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-MainTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Main test failed: $Message"
    }
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($DataRoot)) {
    $DataRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..\data'))
}
$FirstResults = @(& (Join-Path $WindowsRoot 'main.ps1') -DataRoot $DataRoot)
Assert-MainTest `
    -Condition ($FirstResults.Count -eq 1) `
    -Message 'first invocation did not return exactly one build result'
$First = $FirstResults[0]
$ExpectedCoreReleaseRoot = [IO.Path]::GetFullPath(
    (Join-Path $DataRoot 'core.release')
)
$ExpectedEntryReleaseRoot = [IO.Path]::GetFullPath(
    (Join-Path $DataRoot 'entry.release')
)
$ExpectedEntryManagerReleaseRoot = [IO.Path]::GetFullPath(
    (Join-Path $DataRoot 'entry.manager.release')
)
Assert-MainTest `
    -Condition (
        (Split-Path -Path ([string]$First.CoreRelease.Root) -Parent).Equals(
            $ExpectedCoreReleaseRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Split-Path -Path ([string]$First.EntryRelease.Root) -Parent).
            Equals(
            $ExpectedEntryReleaseRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Split-Path -Path ([string]$First.EntryManagerRelease.Root) -Parent).
            Equals(
                $ExpectedEntryManagerReleaseRoot,
                [StringComparison]::OrdinalIgnoreCase
        )
    ) `
    -Message 'main did not publish all three products to their Release stores'

$SecondInvocation = @(
    & (Join-Path $WindowsRoot 'main.ps1') -DataRoot $DataRoot 6>&1
)
$SecondResults = @($SecondInvocation | Where-Object {
    $_ -isnot [Management.Automation.InformationRecord]
})
$SecondMessages = @($SecondInvocation | Where-Object {
    $_ -is [Management.Automation.InformationRecord]
} | ForEach-Object { [string]$_.MessageData })
Assert-MainTest `
    -Condition ($SecondResults.Count -eq 1) `
    -Message 'second invocation did not return exactly one build result'
$Second = $SecondResults[0]
Assert-MainTest `
    -Condition (
        [string]$First.CoreRelease.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
        [string]$First.EntryRelease.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
        [string]$First.EntryManagerRelease.ReleaseId -cmatch
            '^[a-f0-9]{64}$' -and
        [string]$Second.CoreRelease.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
        [string]$Second.EntryRelease.ReleaseId -cmatch '^[a-f0-9]{64}$' -and
        [string]$Second.EntryManagerRelease.ReleaseId -cmatch
            '^[a-f0-9]{64}$' -and
        @($SecondMessages | Where-Object {
            $_ -cmatch '^\[BUILT\] '
        }).Count -eq 3 -and
        @($SecondMessages | Where-Object {
            $_ -cmatch '^\[PUBLISHED\] '
        }).Count -eq 3 -and
        (Split-Path -Path ([string]$Second.CoreRelease.Root) -Parent).
            Equals(
                $ExpectedCoreReleaseRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -and
        (Split-Path -Path ([string]$Second.EntryRelease.Root) -Parent).
            Equals(
                $ExpectedEntryReleaseRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -and
        (Split-Path -Path ([string]$Second.EntryManagerRelease.Root) -Parent).
            Equals(
                $ExpectedEntryManagerReleaseRoot,
                [StringComparison]::OrdinalIgnoreCase
        ) -and
        (Get-Item -LiteralPath $First.CoreRelease.ArtifactPath).Length -gt 0 -and
        (Get-Item -LiteralPath $First.EntryRelease.ArtifactPath).Length -gt 0 -and
        (Get-Item -LiteralPath $First.EntryManagerRelease.ArtifactPath).Length `
            -gt 0 -and
        (Get-Item -LiteralPath $Second.CoreRelease.ArtifactPath).Length -gt 0 -and
        (Get-Item -LiteralPath $Second.EntryRelease.ArtifactPath).Length -gt 0 -and
        (Get-Item -LiteralPath $Second.EntryManagerRelease.ArtifactPath).Length -gt 0
    ) `
    -Message 'explicit Bootstrap did not preserve valid three-product Releases'

Write-Host '[PASS] Windows Bootstrap main end-to-end' -ForegroundColor Green
