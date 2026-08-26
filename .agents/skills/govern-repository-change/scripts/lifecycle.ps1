[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Position = 0)]
    [ValidateSet(
        'status',
        'plan-install', 'install',
        'plan-disable', 'disable',
        'plan-uninstall', 'uninstall'
    )]
    [string]$Action = 'status',

    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$Action = $Action.ToLowerInvariant()

$sharedScriptRoot = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\..\..\.github\rulesets\scripts'
))
Import-Module (Join-Path $PSScriptRoot 'lifecycle-remote.psm1') -Force
Import-Module (Join-Path $sharedScriptRoot 'ruleset-client.psm1') -Force
Import-Module (Join-Path $sharedScriptRoot 'control-plane.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lifecycle-plan.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lifecycle-state.psm1') -Force
Import-Module (Join-Path $sharedScriptRoot 'ruleset-state.psm1') -Force
Import-Module (Join-Path $sharedScriptRoot 'repository.psm1') -Force

function Get-SourceDisposition {
    param($Manifest)

    if ($null -eq $Manifest) {
        return [pscustomobject][ordered]@{
            RemoveDirectories = @()
            RemoveFiles = @()
            RemoveManagedBlocks = @()
            RetainFiles = @()
        }
    }
    return [pscustomobject][ordered]@{
        RemoveDirectories = @($Manifest.versioned.exclusive_directories)
        RemoveFiles = @($Manifest.versioned.removable_files)
        RemoveManagedBlocks = @(
            $Manifest.versioned.managed_blocks | ForEach-Object {
                [pscustomobject][ordered]@{
                    Path = [string]$_.path
                    Begin = [string]$_.begin
                    End = [string]$_.end
                }
            }
        )
        RetainFiles = @($Manifest.versioned.retained_files)
    }
}

function New-LifecycleReport {
    param(
        [string]$Mode,
        [string]$Repository,
        $CandidateSource,
        $DefaultSource,
        [string]$RulesetState,
        $Ruleset,
        $ProductRuleset,
        $Plan,
        [string]$Diagnostic = ''
    )

    $isSourceRemoval = $Mode -cin @('plan-uninstall', 'uninstall')
    $sourceManifest = if ($null -ne $DefaultSource.Manifest) {
        $DefaultSource.Manifest
    }
    else { $CandidateSource.Manifest }
    $overall = if ($DefaultSource.State -cne 'installed') {
        if ($CandidateSource.State -ceq 'installed') {
            'source_pending_default_branch'
        }
        else { 'source_not_installed' }
    }
    elseif ($RulesetState -ceq 'active') { 'active' }
    elseif ($RulesetState -ceq 'disabled') { 'disabled' }
    elseif ($RulesetState -ceq 'absent' -and $isSourceRemoval) {
        'source_removal_pending'
    }
    elseif ($RulesetState -ceq 'absent') { 'source_only' }
    else { 'blocked' }
    return [pscustomobject][ordered]@{
        Mode = $Mode
        Outcome = $Plan.Outcome
        Blocked = $Plan.Blocked
        OverallState = $overall
        CandidateSourceState = $CandidateSource.State
        CandidateSourceDiagnostics = @($CandidateSource.Diagnostics)
        DefaultSourceState = $DefaultSource.State
        DefaultSourceDiagnostics = @($DefaultSource.Diagnostics)
        LocalGitState = 'not_managed'
        RulesetState = $RulesetState
        Repository = $Repository
        Ruleset = if ($null -eq $Ruleset) { $null } else { $Ruleset.name }
        RulesetId = if ($null -eq $Ruleset) { $null } else { $Ruleset.id }
        ProductRulesetState = $ProductRuleset.State
        ProductRulesetId = $ProductRuleset.Id
        ProductRulesetDiagnostic = $ProductRuleset.Diagnostic
        Recovery = if ([string]::IsNullOrWhiteSpace($Diagnostic)) {
            'none'
        }
        else { 'inspect_before_retry' }
        Diagnostic = $Diagnostic
        SourceDisposition = Get-SourceDisposition -Manifest $sourceManifest
        NextAction = $Plan.NextAction
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$RepositoryRoot = Get-RepositoryNormalizedPath -Path $RepositoryRoot
$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$ghswaw = Get-Command ghswaw -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$actualRoot = @(Invoke-RepositoryCommand `
    -Executable $git.Source `
    -Arguments @('-C', $RepositoryRoot, 'rev-parse', '--show-toplevel') `
    -Operation 'Resolve repository root')[-1].Trim()
if (-not (Get-RepositoryNormalizedPath $actualRoot).Equals(
    $RepositoryRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "RepositoryRoot must be the worktree root: $actualRoot"
}
$origin = Get-RepositoryOrigin $git.Source $RepositoryRoot
$repository = $origin.Repository
[void](Invoke-RepositoryCommand `
    -Executable $ghswaw.Source `
    -Arguments @('.doctor') `
    -Operation 'Validate ghswaw')

$candidateSource = Get-GovernanceSourceState `
    -Git $git.Source `
    -RepositoryRoot $RepositoryRoot
$defaultSource = Get-GovernanceSourceState `
    -Git $git.Source `
    -RepositoryRoot $RepositoryRoot `
    -Ref 'origin/main'
$manifest = if ($defaultSource.State -ceq 'installed') {
    $defaultSource.Manifest
}
elseif ($candidateSource.State -ceq 'installed') {
    $candidateSource.Manifest
}
else { $null }

$ruleset = $null
$rulesetState = 'unknown'
$diagnostic = ''
if ($null -ne $manifest) {
    $declaration = @($manifest.github.rulesets)[0]
    $remoteRulesetName = Get-GovernanceRulesetRemoteName $declaration
    $remoteRulesetPrefix = Get-GovernanceRulesetRemotePrefix $declaration
    $ruleset = [pscustomobject]@{
        name = $remoteRulesetName
        id = $null
    }
    $rulesetPath = Join-Path `
        $RepositoryRoot `
        ([string]$declaration.desired_path).Replace('/', '\')
    try {
        $desired = Get-DesiredRuleset `
            -Path $rulesetPath `
            -ExpectedName $remoteRulesetName
        Assert-GovernanceRulesetContract `
            -Ruleset $desired `
            -ExpectedName $remoteRulesetName
        $remote = Get-GovernanceRemoteRuleset `
            -Ghswaw $ghswaw.Source `
            -Repository $repository `
            -Name $remoteRulesetName `
            -ReservedNamePrefix $remoteRulesetPrefix
        $rulesetState = Get-RulesetLifecycleState `
            -Desired $desired `
            -Actual $remote.Actual
        $ruleset.id = $remote.Id
    }
    catch {
        if ([string]$_.Exception.Data['GovernanceRulesetState'] -ceq
            'collision') {
            $rulesetState = 'collision'
        }
        $diagnostic = $_.Exception.Message
    }
}
else {
    $diagnostic = 'No valid ownership manifest is available.'
}
$productRuleset = Get-ProductRulesetStatus `
    -Ghswaw $ghswaw.Source `
    -Repository $repository `
    -RepositoryRoot $RepositoryRoot

$logicalAction = if ($Action.StartsWith('plan-')) {
    $Action.Substring('plan-'.Length)
}
elseif ($Action -ceq 'status') { 'status' }
else { $Action }
$plan = Get-GovernanceLifecyclePlan `
    -Action $logicalAction `
    -SourceState $defaultSource.State `
    -RulesetState $rulesetState `
    -ProductRulesetState $productRuleset.State
$isPlan = $Action.StartsWith('plan-') -or $Action -ceq 'status'
if ($isPlan -or $plan.Blocked -or $plan.Outcome -ceq 'none') {
    New-LifecycleReport $Action $repository $candidateSource $defaultSource `
        $rulesetState $ruleset $productRuleset $plan $diagnostic
    return
}

Assert-GovernanceControlPlaneContext `
    -Git $git.Source `
    -Ghswaw $ghswaw.Source `
    -RepositoryRoot $RepositoryRoot `
    -Repository $repository
$description = "$($plan.Outcome) Ruleset '$($ruleset.name)'"
if (-not $PSCmdlet.ShouldProcess($repository, $description)) {
    New-LifecycleReport $Action $repository $candidateSource $defaultSource `
        $rulesetState $ruleset $productRuleset $plan $diagnostic
    return
}
Assert-GovernanceControlPlaneContext `
    -Git $git.Source `
    -Ghswaw $ghswaw.Source `
    -RepositoryRoot $RepositoryRoot `
    -Repository $repository
$preMutationRemote = Get-GovernanceRemoteRuleset `
    -Ghswaw $ghswaw.Source `
    -Repository $repository `
    -Name $remoteRulesetName `
    -ReservedNamePrefix $remoteRulesetPrefix
$preMutationState = Get-RulesetLifecycleState `
    -Desired $desired `
    -Actual $preMutationRemote.Actual
if ($preMutationState -cne $rulesetState -or
    [string]$preMutationRemote.Id -cne [string]$ruleset.id) {
    throw (
        'The governance Ruleset changed after planning. No mutation was ' +
        'attempted; run status and plan again.'
    )
}
if ($plan.Outcome -ceq 'delete') {
    $preDeleteProduct = Get-ProductRulesetStatus `
        -Ghswaw $ghswaw.Source `
        -Repository $repository `
        -RepositoryRoot $RepositoryRoot
    if ($preDeleteProduct.State -cne 'in_sync' -or
        [string]$preDeleteProduct.Id -cne [string]$productRuleset.Id) {
        throw (
            'protect-main changed after uninstall planning. No governance ' +
            'Ruleset deletion was attempted; reconcile both Rulesets and plan again.'
        )
    }
}

$payloadPath = $null
try {
    if ($plan.Outcome -ceq 'create') {
        $payloadPath = New-RulesetPayloadSnapshot -Ruleset $desired
        Set-GitHubRuleset `
            -Ghswaw $ghswaw.Source `
            -Repository $repository `
            -PayloadPath $payloadPath
    }
    elseif ($plan.Outcome -ceq 'enable') {
        $payloadPath = New-RulesetPayloadSnapshot -Ruleset $desired
        Set-GitHubRuleset `
            -Ghswaw $ghswaw.Source `
            -Repository $repository `
            -PayloadPath $payloadPath `
            -RulesetId $ruleset.id
    }
    elseif ($plan.Outcome -ceq 'disable') {
        $disabled = Get-RulesetProjection `
            -Ruleset $desired `
            -Enforcement 'disabled'
        $payloadPath = New-RulesetPayloadSnapshot -Ruleset $disabled
        Set-GitHubRuleset `
            -Ghswaw $ghswaw.Source `
            -Repository $repository `
            -PayloadPath $payloadPath `
            -RulesetId $ruleset.id
    }
    elseif ($plan.Outcome -ceq 'delete') {
        Remove-GitHubRuleset `
            -Ghswaw $ghswaw.Source `
            -Repository $repository `
            -RulesetId $ruleset.id
    }
}
catch {
    throw (
        "The lifecycle '$($plan.Outcome)' result is unknown. Do not retry " +
        "automatically; run 'lifecycle.ps1 status' and inspect GitHub first. " +
        $_.Exception.Message
    )
}
finally {
    if ($null -ne $payloadPath -and [IO.File]::Exists($payloadPath)) {
        try {
            [IO.File]::Delete($payloadPath)
        }
        catch {
            Write-Warning -WarningAction Continue -Message (
                'The temporary Ruleset payload could not be removed. This ' +
                'cleanup failure does not change the remote mutation result: ' +
                $_.Exception.Message
            )
        }
    }
}

try {
    $verifiedRemote = Get-GovernanceRemoteRuleset `
        -Ghswaw $ghswaw.Source `
        -Repository $repository `
        -Name $remoteRulesetName `
        -ReservedNamePrefix $remoteRulesetPrefix
    $verifiedState = Get-RulesetLifecycleState `
        -Desired $desired `
        -Actual $verifiedRemote.Actual
}
catch {
    throw (
        'The lifecycle request completed, but verification is unknown. Do not ' +
        "retry automatically; run 'lifecycle.ps1 status'. " +
        $_.Exception.Message
    )
}
$expectedState = if ($plan.Outcome -cin @('create', 'enable')) { 'active' }
    elseif ($plan.Outcome -ceq 'disable') { 'disabled' }
    else { 'absent' }
if ($verifiedState -cne $expectedState) {
    throw (
        "Lifecycle verification expected '$expectedState' but observed " +
        "'$verifiedState'. Stop and inspect the remote Ruleset."
    )
}
if ($plan.Outcome -ceq 'delete') {
    $verifiedProduct = Get-ProductRulesetStatus `
        -Ghswaw $ghswaw.Source `
        -Repository $repository `
        -RepositoryRoot $RepositoryRoot
    if ($verifiedProduct.State -cne 'in_sync' -or
        [string]$verifiedProduct.Id -cne [string]$productRuleset.Id) {
        throw (
            'The governance Ruleset was deleted and verified absent, but ' +
            'protect-main changed concurrently. Do not remove governance ' +
            'source; inspect and reconcile protect-main first.'
        )
    }
    $productRuleset = $verifiedProduct
}
$verifiedRuleset = [pscustomobject]@{
    name = $remoteRulesetName
    id = $verifiedRemote.Id
}
$completedPlan = [pscustomobject]@{
    Outcome = $plan.Outcome
    Blocked = $false
    NextAction = if ($plan.Outcome -ceq 'delete') {
        'Remove the declared source through a reviewed PR.'
    }
    else { 'Lifecycle mutation completed and was verified.' }
}
New-LifecycleReport $Action $repository $candidateSource $defaultSource `
    $verifiedState $verifiedRuleset $productRuleset $completedPlan
