[CmdletBinding()]
param([string]$VarRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-MainTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Main test failed: $Message"
    }
}

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($VarRoot)) {
    $VarRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
}
$EntryRoot = Join-Path $VarRoot (
    "var_entry\_test-main-$([Guid]::NewGuid().ToString('N'))"
)
try {
    $FirstResults = @(& (Join-Path $WindowsRoot 'main.ps1') `
        -VarRoot $VarRoot `
        -EntryRoot $EntryRoot)
    Assert-MainTest `
        -Condition ($FirstResults.Count -eq 1) `
        -Message 'first invocation did not return exactly one Release'
    $First = $FirstResults[0]
    [IO.File]::WriteAllText(
        [string]$First.ArtifactPath,
        'corrupt',
        [Text.UTF8Encoding]::new($false)
    )

    $SecondResults = @(& (Join-Path $WindowsRoot 'main.ps1') `
        -VarRoot $VarRoot `
        -EntryRoot $EntryRoot)
    Assert-MainTest `
        -Condition ($SecondResults.Count -eq 1) `
        -Message 'second invocation did not return exactly one Release'
    $Second = $SecondResults[0]
    Assert-MainTest `
        -Condition (
            [string]$Second.ReleaseId -ceq [string]$First.ReleaseId -and
            (Get-Item -LiteralPath $Second.ArtifactPath).Length -gt 7
        ) `
        -Message 'explicit Bootstrap did not rebuild and repair its Release'
} finally {
    if ([IO.Directory]::Exists($EntryRoot)) {
        [IO.Directory]::Delete($EntryRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap main end-to-end' -ForegroundColor Green
