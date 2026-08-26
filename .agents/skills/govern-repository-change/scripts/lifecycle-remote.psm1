$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$sharedScriptRoot = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\..\..\.github\rulesets\scripts'
))
Import-Module (Join-Path $sharedScriptRoot 'ruleset-client.psm1') -Force
Import-Module (Join-Path $sharedScriptRoot 'ruleset-state.psm1') -Force

function Get-GovernanceRemoteRuleset {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ReservedNamePrefix
    )

    $remote = Get-RemoteRuleset `
        -Ghswaw $Ghswaw `
        -Repository $Repository `
        -Name $Name `
        -ReservedNamePrefix $ReservedNamePrefix
    $collisions = @($remote.ReservedNameCollisions)
    if ($collisions.Count -gt 0) {
        $names = @($collisions | ForEach-Object { "'$($_.Name)'" }) -join ', '
        $exception = [InvalidOperationException]::new((
            'Reserved governance Ruleset namespace contains unexpected ' +
            "sibling identities: $names. Inspect and resolve them explicitly."
        ))
        $exception.Data['GovernanceRulesetState'] = 'collision'
        throw $exception
    }
    return $remote
}

function Get-ProductRulesetStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    try {
        $path = Join-Path `
            $RepositoryRoot `
            '.github\rulesets\protect-main.json'
        $desired = Get-DesiredRuleset `
            -Path $path `
            -ExpectedName 'protect-main'
        $declaredContexts = @(Get-RulesetRequiredContexts $desired)
        if ([string]$desired.target -cne 'branch' -or
            [string]$desired.enforcement -cne 'active' -or
            $declaredContexts -ccontains 'Change policy' -or
            $declaredContexts -ccontains 'Governance validation') {
            throw (
                'The retained product Ruleset declaration must be active, ' +
                'target branches, and contain no governance required checks.'
            )
        }
        $remote = Get-RemoteRuleset `
            -Ghswaw $Ghswaw `
            -Repository $Repository `
            -Name 'protect-main'
        $state = if ($null -eq $remote.Actual) {
            'absent'
        }
        elseif (Test-RulesetDesiredState `
            -Desired $desired `
            -Actual $remote.Actual) {
            'in_sync'
        }
        else { 'drift' }
        return [pscustomobject][ordered]@{
            State = $state
            Id = $remote.Id
            Diagnostic = ''
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            State = 'unknown'
            Id = $null
            Diagnostic = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function @(
    'Get-GovernanceRemoteRuleset',
    'Get-ProductRulesetStatus'
)
