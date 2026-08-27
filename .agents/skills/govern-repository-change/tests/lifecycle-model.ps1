[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $skillRoot '..\..\..'))
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
Import-Module `
    (Join-Path $repositoryRoot '.github\rulesets\scripts\ruleset-state.psm1') `
    -Force
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
    @('status', 'installed', 'legacy_active', 'in_sync', 'observed', $false),
    @('install', 'installed', 'absent', 'in_sync', 'create', $false),
    @('install', 'installed', 'disabled', 'in_sync', 'enable', $false),
    @('install', 'installed', 'legacy_active', 'in_sync', 'migrate', $false),
    @('install', 'installed', 'active', 'in_sync', 'none', $false),
    @('disable', 'installed', 'legacy_active', 'in_sync', 'blocked', $true),
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

$desiredPath = Join-Path `
    $repositoryRoot `
    '.github\rulesets\swaw-change-governance.json'
$desiredName = [string](
    Get-Content -LiteralPath $desiredPath -Raw | ConvertFrom-Json
).name
$desired = Get-DesiredRuleset -Path $desiredPath -ExpectedName $desiredName
$legacy = $desired | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$legacyRule = @($legacy.rules | Where-Object {
    $_.type -ceq 'required_status_checks'
})[0]
$legacyRule.parameters.required_status_checks = @(
    @($legacyRule.parameters.required_status_checks) + @(
        [pscustomobject][ordered]@{
            context = 'Governance validation'
            integration_id = 15368
        }
    )
)
Assert-Equal 'legacy_active' (Get-RulesetLifecycleState $desired $legacy) `
    'the exact previous active projection is migratable'

$wrongIntegration = $legacy | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$wrongRule = @($wrongIntegration.rules | Where-Object {
    $_.type -ceq 'required_status_checks'
})[0]
@($wrongRule.parameters.required_status_checks)[1].integration_id = 1
Assert-Equal 'drift' (Get-RulesetLifecycleState $desired $wrongIntegration) `
    'a lookalike predecessor with the wrong integration remains drift'

$extraCheck = $legacy | ConvertTo-Json -Depth 100 | ConvertFrom-Json
$extraRule = @($extraCheck.rules | Where-Object {
    $_.type -ceq 'required_status_checks'
})[0]
$extraRule.parameters.required_status_checks = @(
    @($extraRule.parameters.required_status_checks) + @(
        [pscustomobject][ordered]@{
            context = 'Unknown check'
            integration_id = 15368
        }
    )
)
Assert-Equal 'drift' (Get-RulesetLifecycleState $desired $extraCheck) `
    'an active projection with any extra check remains drift'

Write-Output (
    "PASS: $assertionCount assertions; lifecycle manifest and planning " +
    'contracts were validated offline.'
)
