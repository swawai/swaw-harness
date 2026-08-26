[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'plan', 'apply')]
    [string]$Action = 'status',

    [string]$RepositoryRoot = '',

    [string]$RulesetPath = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Action = $Action.ToLowerInvariant()

Import-Module (Join-Path $PSScriptRoot 'governance.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ruleset-state.psm1') -Force

function Invoke-RulesetApi {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    return Invoke-GovernanceCommand `
        -Executable $Ghswaw `
        -Arguments (@(
            'api',
            '-H', 'Accept: application/vnd.github+json',
            '-H', 'X-GitHub-Api-Version: 2026-03-10'
        ) + $Arguments) `
        -Operation $Operation
}

function Get-RemoteRulesetState {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)]$Desired
    )

    $pageSize = 100
    $page = 1
    $summaries = @()
    do {
        $listOutput = @(Invoke-RulesetApi `
            -Ghswaw $Ghswaw `
            -Arguments @(
                '--method', 'GET',
                "repos/$Repository/rulesets",
                '-f', 'includes_parents=false',
                '-f', "per_page=$pageSize",
                '-f', "page=$page"
            ) `
            -Operation "List GitHub Rulesets page $page")
        try {
            $pageItems = @((($listOutput -join "`n") | ConvertFrom-Json))
        }
        catch {
            throw (
                "GitHub Ruleset list page $page response is invalid JSON: " +
                $_.Exception.Message
            )
        }
        $summaries += $pageItems
        $page++
    } while ($pageItems.Count -eq $pageSize)

    $matches = @($summaries | Where-Object {
        [string]$_.name -ceq [string]$Desired.name
    })
    foreach ($match in $matches) {
        Assert-RepositoryRulesetOwnership `
            -Ruleset $match `
            -Repository $Repository `
            -Owner "GitHub Ruleset summary '$($Desired.name)'"
    }
    if ($matches.Count -gt 1) {
        throw "GitHub returned multiple Rulesets named '$($Desired.name)'."
    }
    if ($matches.Count -eq 0) {
        return [pscustomobject][ordered]@{
            State = 'absent'
            Id = $null
            Actual = $null
        }
    }

    $rulesetId = [long]$matches[0].id
    if ($rulesetId -le 0) {
        throw "GitHub Ruleset '$($Desired.name)' has an invalid id."
    }
    $detailOutput = @(Invoke-RulesetApi `
        -Ghswaw $Ghswaw `
        -Arguments @(
            '--method', 'GET',
            "repos/$Repository/rulesets/$rulesetId"
        ) `
        -Operation 'Read GitHub Ruleset')
    try {
        $detail = ($detailOutput -join "`n") | ConvertFrom-Json
    }
    catch {
        throw "GitHub Ruleset response is invalid JSON: $($_.Exception.Message)"
    }
    Assert-RepositoryRulesetOwnership `
        -Ruleset $detail `
        -Repository $Repository `
        -Owner "GitHub Ruleset '$($Desired.name)'"
    $actual = Select-RulesetConfiguration -Ruleset $detail
    $isEqual = Test-RulesetDesiredState `
        -Desired $Desired `
        -Actual $actual
    return [pscustomobject][ordered]@{
        State = if ($isEqual) { 'in_sync' } else { 'drift' }
        Id = $rulesetId
        Actual = $actual
    }
}

function New-RulesetReport {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Desired,
        [Parameter(Mandatory = $true)]$State
    )

    return [pscustomobject][ordered]@{
        Mode = $Mode
        Outcome = $Outcome
        State = $State.State
        Repository = $Repository
        Ruleset = [string]$Desired.name
        RulesetId = $State.Id
        LocalPath = $Path
        Enforcement = [string]$Desired.enforcement
        Target = [string]$Desired.target
        RuleTypes = @($Desired.rules | ForEach-Object { [string]$_.type })
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$RepositoryRoot = Get-GovernanceNormalizedPath -Path $RepositoryRoot
if ([string]::IsNullOrWhiteSpace($RulesetPath)) {
    $RulesetPath = Join-Path `
        $RepositoryRoot `
        '.github\rulesets\protect-main.json'
}
$RulesetPath = [IO.Path]::GetFullPath($RulesetPath)

$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$ghswaw = Get-Command ghswaw -CommandType Application -ErrorAction Stop |
    Select-Object -First 1

$actualRootOutput = @(Invoke-GovernanceCommand `
    -Executable $git.Source `
    -Arguments @('-C', $RepositoryRoot, 'rev-parse', '--show-toplevel') `
    -Operation 'Resolve repository root')
$actualRoot = Get-GovernanceNormalizedPath -Path $actualRootOutput[-1].Trim()
if (-not $actualRoot.Equals(
    $RepositoryRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "RepositoryRoot must be the worktree root: $actualRoot"
}

$desired = Get-DesiredRuleset -Path $RulesetPath
$origin = Get-GovernanceOrigin `
    -Git $git.Source `
    -RepositoryRoot $RepositoryRoot
$repository = $origin.Repository

[void](Invoke-GovernanceCommand `
    -Executable $ghswaw.Source `
    -Arguments @('.doctor') `
    -Operation 'Validate ghswaw')
$state = Get-RemoteRulesetState `
    -Ghswaw $ghswaw.Source `
    -Repository $repository `
    -Desired $desired

if ($Action -ceq 'status') {
    New-RulesetReport `
        -Mode $Action `
        -Outcome 'observed' `
        -Repository $repository `
        -Path $RulesetPath `
        -Desired $desired `
        -State $state
    return
}

$operation = if ($state.State -ceq 'absent') {
    'create'
}
elseif ($state.State -ceq 'drift') {
    'update'
}
else {
    'none'
}
if ($Action -ceq 'plan' -or $operation -ceq 'none') {
    New-RulesetReport `
        -Mode $Action `
        -Outcome $operation `
        -Repository $repository `
        -Path $RulesetPath `
        -Desired $desired `
        -State $state
    return
}

$description = if ($operation -ceq 'create') {
    "Create Ruleset '$($desired.name)'"
}
else {
    "Update Ruleset '$($desired.name)' (#$($state.Id))"
}
if (-not $PSCmdlet.ShouldProcess($repository, $description)) {
    New-RulesetReport `
        -Mode $Action `
        -Outcome $operation `
        -Repository $repository `
        -Path $RulesetPath `
        -Desired $desired `
        -State $state
    return
}

$method = if ($operation -ceq 'create') { 'POST' } else { 'PUT' }
$endpoint = if ($operation -ceq 'create') {
    "repos/$repository/rulesets"
}
else {
    "repos/$repository/rulesets/$($state.Id)"
}
try {
    [void](Invoke-RulesetApi `
        -Ghswaw $ghswaw.Source `
        -Arguments @(
            '--method', $method,
            $endpoint,
            '--input', $RulesetPath
        ) `
        -Operation "$operation GitHub Ruleset")
}
catch {
    throw (
        "The Ruleset $operation result is unknown. Do not retry automatically; " +
        "run 'ruleset.ps1 status' and inspect GitHub first. " +
        $_.Exception.Message
    )
}

try {
    $verified = Get-RemoteRulesetState `
        -Ghswaw $ghswaw.Source `
        -Repository $repository `
        -Desired $desired
}
catch {
    throw (
        "The Ruleset $operation request completed, but verification result " +
        "is unknown. Do not retry automatically; run 'ruleset.ps1 status' " +
        'and inspect GitHub first. ' +
        $_.Exception.Message
    )
}
if ($verified.State -cne 'in_sync') {
    throw (
        "GitHub accepted the Ruleset $operation, but verification returned " +
        "'$($verified.State)'. Stop and inspect the remote Ruleset."
    )
}
New-RulesetReport `
    -Mode $Action `
    -Outcome $operation `
    -Repository $repository `
    -Path $RulesetPath `
    -Desired $desired `
    -State $verified
