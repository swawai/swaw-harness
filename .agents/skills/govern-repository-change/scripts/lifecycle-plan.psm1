$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-GovernanceLifecyclePlan {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('status', 'install', 'disable', 'uninstall')]
        [string]$Action,
        [Parameter(Mandatory = $true)][string]$SourceState,
        [Parameter(Mandatory = $true)][string]$RulesetState,
        [Parameter(Mandatory = $true)][string]$ProductRulesetState
    )

    $outcome = 'none'
    $blocked = $false
    $next = 'No control-plane change is required.'
    if ($Action -ceq 'status') {
        $outcome = 'observed'
        $blocked = $SourceState -cne 'installed' -or
            $RulesetState -cin @('drift', 'unknown', 'collision')
        $next = if ($SourceState -ceq 'absent') {
            'Install and merge the declared governance source first.'
        }
        elseif ($SourceState -cne 'installed') {
            'Repair the declared governance source through a reviewed PR first.'
        }
        elseif ($RulesetState -ceq 'active') {
            'Governance source and control plane are active.'
        }
        elseif ($RulesetState -ceq 'disabled') {
            'Governance source is installed and enforcement is disabled.'
        }
        elseif ($RulesetState -ceq 'absent') {
            'Governance source is installed but its control plane is absent.'
        }
        else { 'Inspect the remote Ruleset before any mutation.' }
    }
    elseif ($SourceState -cne 'installed') {
        $blocked = $true
        $outcome = 'blocked'
        $next = if ($SourceState -ceq 'absent') {
            'Install and merge the declared governance source first.'
        }
        else {
            'Repair the declared governance source through a reviewed PR first.'
        }
    }
    elseif ($RulesetState -ceq 'collision') {
        $blocked = $true
        $outcome = 'blocked'
        $next = (
            'Resolve the reserved sibling identity explicitly; do not create, ' +
            'adopt, overwrite, or delete it automatically.'
        )
    }
    elseif ($RulesetState -cin @('drift', 'unknown')) {
        $blocked = $true
        $outcome = 'blocked'
        $next = 'Inspect the remote Ruleset; lifecycle actions never reconcile drift.'
    }
    elseif ($Action -ceq 'install') {
        if ($RulesetState -ceq 'absent') { $outcome = 'create' }
        elseif ($RulesetState -ceq 'disabled') { $outcome = 'enable' }
        $next = if ($outcome -ceq 'none') {
            'Governance is already active.'
        }
        else { 'Apply the plan, then verify the Ruleset is active.' }
    }
    elseif ($Action -ceq 'disable') {
        if ($RulesetState -ceq 'active') { $outcome = 'disable' }
        $next = if ($outcome -ceq 'none') {
            'Governance enforcement is already inactive.'
        }
        else { 'Apply the plan, then verify the Ruleset is disabled.' }
    }
    elseif ($Action -ceq 'uninstall') {
        if ($ProductRulesetState -cne 'in_sync') {
            $blocked = $true
            $outcome = 'blocked'
            $next = (
                'Reconcile and verify protect-main without governance checks ' +
                'before disabling or uninstalling governance.'
            )
        }
        elseif ($RulesetState -ceq 'active') {
            $blocked = $true
            $outcome = 'blocked'
            $next = 'Disable governance before uninstalling it.'
        }
        elseif ($RulesetState -ceq 'disabled') {
            $outcome = 'delete'
            $next = 'Delete the Ruleset, then remove source through a reviewed PR.'
        }
        else {
            $next = 'Remove the remaining source through a reviewed PR.'
        }
    }
    return [pscustomobject][ordered]@{
        Action = $Action
        Outcome = $outcome
        Blocked = $blocked
        NextAction = $next
    }
}

Export-ModuleMember -Function 'Get-GovernanceLifecyclePlan'
