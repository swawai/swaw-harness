[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $skillRoot 'ownership.json'
$assertionCount = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)

    if ($Expected -cne $Actual) {
        throw "Assertion failed: $Message (expected '$Expected', actual '$Actual')"
    }
    $script:assertionCount++
}

function Assert-Contains {
    param([string]$Text, [string]$Fragment, [string]$Message)

    if (-not $Text.Contains($Fragment)) {
        throw "Assertion failed: $Message (missing '$Fragment')"
    }
    $script:assertionCount++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Fragment, [string]$Message)

    try { & $Action | Out-Null }
    catch {
        Assert-Contains `
            -Text $_.Exception.Message `
            -Fragment $Fragment `
            -Message "$Message; actual error: $($_.Exception.Message)"
        return
    }
    throw "Assertion failed: $Message (no exception was thrown)"
}

Import-Module (Join-Path $skillRoot 'scripts\lifecycle-plan.psm1') -Force
Import-Module (Join-Path $skillRoot 'scripts\lifecycle-state.psm1') -Force
$manifestJson = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8)
$manifest = ConvertFrom-GovernanceOwnershipManifest `
    -Json $manifestJson `
    -Owner 'test manifest'
Assert-Equal `
    -Expected 'swaw.repository-change-governance' `
    -Actual $manifest.id `
    -Message 'valid manifest identity'

foreach ($invalid in @(
    [pscustomobject]@{
        Name = 'string schema version'
        Transform = { param($m) $m.schema_version = '1' }
        Error = 'schema_version must be 1'
    },
    [pscustomobject]@{
        Name = 'unknown property'
        Transform = { param($m) $m | Add-Member extra $true }
        Error = 'unsupported property'
    },
    [pscustomobject]@{
        Name = 'unsafe path'
        Transform = {
            param($m)
            $m.versioned.removable_files[0] = '../escape'
        }
        Error = 'unsafe path segment'
    },
    [pscustomobject]@{
        Name = 'case duplicate'
        Transform = {
            param($m)
            $m.versioned.removable_files[1] = (
                $m.versioned.removable_files[0].ToUpperInvariant()
            )
        }
        Error = 'overlaps'
    },
    [pscustomobject]@{
        Name = 'retained ownership overlap'
        Transform = {
            param($m)
            $m.versioned.retained_files[0] = $m.versioned.removable_files[0]
        }
        Error = 'overlaps removable ownership'
    },
    [pscustomobject]@{
        Name = 'future local setting'
        Transform = {
            param($m)
            $m.local_git.settings = @([pscustomobject]@{ key = 'x' })
        }
        Error = 'reserved for a later schema'
    },
    [pscustomobject]@{
        Name = 'baseline takeover'
        Transform = { param($m) $m.github.rulesets[0].name = 'protect-main' }
        Error = 'dedicated governance Ruleset identity'
    },
    [pscustomobject]@{
        Name = 'invalid ownership token'
        Transform = {
            param($m)
            $m.github.rulesets[0].ownership_token = 'shared-name'
        }
        Error = '32 lowercase hex digits'
    }
)) {
    $document = $manifestJson | ConvertFrom-Json
    & $invalid.Transform $document
    Assert-Throws `
        -Action {
            ConvertFrom-GovernanceOwnershipManifest `
                -Json ($document | ConvertTo-Json -Depth 100) `
                -Owner $invalid.Name
        } `
        -Fragment $invalid.Error `
        -Message $invalid.Name
}

foreach ($case in @(
    @('install', 'installed', 'absent', 'in_sync', 'create', $false),
    @('install', 'installed', 'disabled', 'in_sync', 'enable', $false),
    @('install', 'installed', 'active', 'in_sync', 'none', $false),
    @('disable', 'installed', 'active', 'in_sync', 'disable', $false),
    @('disable', 'installed', 'disabled', 'in_sync', 'none', $false),
    @('uninstall', 'installed', 'active', 'in_sync', 'blocked', $true),
    @('uninstall', 'installed', 'disabled', 'in_sync', 'delete', $false),
    @('uninstall', 'installed', 'disabled', 'drift', 'blocked', $true),
    @('install', 'partial', 'absent', 'in_sync', 'blocked', $true),
    @('install', 'installed', 'drift', 'in_sync', 'blocked', $true),
    @('install', 'installed', 'collision', 'in_sync', 'blocked', $true)
)) {
    $plan = Get-GovernanceLifecyclePlan `
        -Action $case[0] `
        -SourceState $case[1] `
        -RulesetState $case[2] `
        -ProductRulesetState $case[3]
    Assert-Equal $case[4] $plan.Outcome "plan $($case[0])/$($case[2])"
    Assert-Equal $case[5] $plan.Blocked "blocked $($case[0])/$($case[2])"
}

Write-Output (
    "PASS: $assertionCount assertions; lifecycle manifest and planning " +
    'contracts were validated offline.'
)
