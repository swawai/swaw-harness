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

Import-Module (Join-Path $PSScriptRoot 'ruleset-client.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'control-plane.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ruleset-state.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'repository.psm1') -Force

function Get-RemoteRulesetState {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)]$Desired
    )

    $remote = Get-RemoteRuleset `
        -Ghswaw $Ghswaw `
        -Repository $Repository `
        -Name ([string]$Desired.name)
    $isEqual = $null -ne $remote.Actual -and (Test-RulesetDesiredState `
        -Desired $Desired `
        -Actual $remote.Actual)
    return [pscustomobject][ordered]@{
        State = if ($null -eq $remote.Actual) {
            'absent'
        }
        elseif ($isEqual) {
            'in_sync'
        }
        else {
            'drift'
        }
        Id = $remote.Id
        Actual = $remote.Actual
    }
}

function New-RulesetReport {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Desired,
        [Parameter(Mandatory = $true)]$State,
        [bool]$RequiresGovernanceActivation = $false
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
        RequiresGovernanceActivation = $RequiresGovernanceActivation
    }
}

function Assert-GovernanceMigrationReady {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    $lifecycleStatePath = Join-Path $RepositoryRoot (
        '.agents\skills\govern-repository-change\scripts\' +
        'lifecycle-state.psm1'
    )
    if (-not [IO.File]::Exists($lifecycleStatePath)) {
        $governanceSource = @(Invoke-RepositoryCommand `
            -Executable $Git `
            -Arguments @(
                '-C', $RepositoryRoot,
                'ls-tree', '-r', '--name-only', 'origin/main', '--',
                '.agents/skills/govern-repository-change',
                '.github/workflows/change-policy.yml',
                '.github/workflows/validate-governance.yml',
                '.github/rulesets/swaw-change-governance.json'
            ) `
            -Operation 'Inspect governance source on main')
        if ($governanceSource.Count -eq 0) {
            Write-Warning (
                'Governance source is absent on main. Continuing the retained ' +
                'product baseline recovery so stale governance checks cannot ' +
                'lock the repository.'
            )
            return
        }
        throw (
            'Governance lifecycle source is incomplete while retiring Change ' +
            'policy from protect-main. Repair the reviewed governance source ' +
            'and activate its dedicated Ruleset before retrying. Found: ' +
            ($governanceSource -join ', ')
        )
    }
    Import-Module $lifecycleStatePath -Force

    $source = Get-GovernanceSourceState `
        -Git $Git `
        -RepositoryRoot $RepositoryRoot `
        -Ref 'origin/main'
    if ($source.State -cne 'installed') {
        throw 'Governance source must be complete on main before baseline migration.'
    }
    $declaration = @($source.Manifest.github.rulesets)[0]
    $remoteName = Get-GovernanceRulesetRemoteName $declaration
    $remotePrefix = Get-GovernanceRulesetRemotePrefix $declaration
    $path = Join-Path `
        $RepositoryRoot `
        ([string]$declaration.desired_path).Replace('/', '\')
    $governanceDesired = Get-DesiredRuleset $path $remoteName
    Assert-GovernanceRulesetContract $governanceDesired $remoteName
    $governanceRemote = Get-RemoteRuleset `
        -Ghswaw $Ghswaw `
        -Repository $Repository `
        -Name $remoteName `
        -ReservedNamePrefix $remotePrefix
    $siblings = @($governanceRemote.ReservedNameCollisions)
    if ($siblings.Count -gt 0) {
        $names = @($siblings | ForEach-Object { "'$($_.Name)'" }) -join ', '
        throw (
            'Reserved governance Ruleset namespace contains unexpected ' +
            "sibling identities: $names. Inspect and resolve them explicitly."
        )
    }
    $governanceState = Get-RulesetLifecycleState `
        $governanceDesired `
        $governanceRemote.Actual
    if ($governanceState -cne 'active') {
        throw (
            'Activate and verify the dedicated governance Ruleset before ' +
            'removing Change policy from protect-main.'
        )
    }
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..'
}
$RepositoryRoot = Get-RepositoryNormalizedPath -Path $RepositoryRoot
if ([string]::IsNullOrWhiteSpace($RulesetPath)) {
    $RulesetPath = Join-Path `
        $RepositoryRoot `
        '.github\rulesets\protect-main.json'
}
$RulesetPath = [IO.Path]::GetFullPath($RulesetPath)
$rulesetFileName = [IO.Path]::GetFileName($RulesetPath)
if ($rulesetFileName -cne 'protect-main.json') {
    throw (
        "Ruleset file '$rulesetFileName' is not the product baseline. " +
        'Governance enforcement must use lifecycle.ps1.'
    )
}
$expectedRulesetName = 'protect-main'
$declaredRulesetPath = [IO.Path]::GetFullPath((Join-Path `
    $RepositoryRoot `
    ".github\rulesets\$rulesetFileName"
))
if (-not $RulesetPath.Equals(
    $declaredRulesetPath,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "RulesetPath must identify the repository declaration: $declaredRulesetPath"
}

$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$ghswaw = Get-Command ghswaw -CommandType Application -ErrorAction Stop |
    Select-Object -First 1

$actualRootOutput = @(Invoke-RepositoryCommand `
    -Executable $git.Source `
    -Arguments @('-C', $RepositoryRoot, 'rev-parse', '--show-toplevel') `
    -Operation 'Resolve repository root')
$actualRoot = Get-RepositoryNormalizedPath -Path $actualRootOutput[-1].Trim()
if (-not $actualRoot.Equals(
    $RepositoryRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "RepositoryRoot must be the worktree root: $actualRoot"
}

$desired = Get-DesiredRuleset `
    -Path $RulesetPath `
    -ExpectedName $expectedRulesetName
$origin = Get-RepositoryOrigin `
    -Git $git.Source `
    -RepositoryRoot $RepositoryRoot
$repository = $origin.Repository

[void](Invoke-RepositoryCommand `
    -Executable $ghswaw.Source `
    -Arguments @('.doctor') `
    -Operation 'Validate ghswaw')
$state = Get-RemoteRulesetState `
    -Ghswaw $ghswaw.Source `
    -Repository $repository `
    -Desired $desired
$desiredContexts = @(Get-RulesetRequiredContexts $desired)
$actualContexts = if ($null -eq $state.Actual) {
    @()
}
else { @(Get-RulesetRequiredContexts $state.Actual) }
$governanceContexts = @('Change policy', 'Governance validation')
$requiresGovernanceActivation = @($actualContexts | Where-Object {
    $governanceContexts -ccontains $_ -and $desiredContexts -cnotcontains $_
}).Count -gt 0

if ($Action -ceq 'status') {
    New-RulesetReport `
        -Mode $Action `
        -Outcome 'observed' `
        -Repository $repository `
        -Path $RulesetPath `
        -Desired $desired `
        -State $state `
        -RequiresGovernanceActivation $requiresGovernanceActivation
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
        -State $state `
        -RequiresGovernanceActivation $requiresGovernanceActivation
    return
}

$description = if ($operation -ceq 'create') {
    "Create Ruleset '$($desired.name)'"
}
else {
    "Update Ruleset '$($desired.name)' (#$($state.Id))"
}
Assert-GovernanceControlPlaneContext `
    -Git $git.Source `
    -Ghswaw $ghswaw.Source `
    -RepositoryRoot $RepositoryRoot `
    -Repository $repository
if ($requiresGovernanceActivation) {
    Assert-GovernanceMigrationReady `
        -Git $git.Source `
        -Ghswaw $ghswaw.Source `
        -RepositoryRoot $RepositoryRoot `
        -Repository $repository
}
if (-not $PSCmdlet.ShouldProcess($repository, $description)) {
    New-RulesetReport `
        -Mode $Action `
        -Outcome $operation `
        -Repository $repository `
        -Path $RulesetPath `
        -Desired $desired `
        -State $state `
        -RequiresGovernanceActivation $requiresGovernanceActivation
    return
}

Assert-GovernanceControlPlaneContext `
    -Git $git.Source `
    -Ghswaw $ghswaw.Source `
    -RepositoryRoot $RepositoryRoot `
    -Repository $repository
if ($requiresGovernanceActivation) {
    Assert-GovernanceMigrationReady `
        -Git $git.Source `
        -Ghswaw $ghswaw.Source `
        -RepositoryRoot $RepositoryRoot `
        -Repository $repository
}
$preMutationState = Get-RemoteRulesetState `
    -Ghswaw $ghswaw.Source `
    -Repository $repository `
    -Desired $desired
$sameActual = Test-RulesetDesiredState `
    -Desired $state.Actual `
    -Actual $preMutationState.Actual
if ($preMutationState.State -cne $state.State -or
    [string]$preMutationState.Id -cne [string]$state.Id -or
    -not $sameActual) {
    throw (
        'protect-main changed after planning. No mutation was attempted; ' +
        'run status and plan again.'
    )
}

$payloadPath = $null
try {
    $mutationRulesetId = if ($operation -ceq 'create') {
        0
    }
    else {
        $state.Id
    }
    $payloadPath = New-RulesetPayloadSnapshot -Ruleset $desired
    Set-GitHubRuleset `
        -Ghswaw $ghswaw.Source `
        -Repository $repository `
        -PayloadPath $payloadPath `
        -RulesetId $mutationRulesetId
}
catch {
    throw (
        "The Ruleset $operation result is unknown. Do not retry automatically; " +
        "run 'protect-main.ps1 status' and inspect GitHub first. " +
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
    $verified = Get-RemoteRulesetState `
        -Ghswaw $ghswaw.Source `
        -Repository $repository `
        -Desired $desired
}
catch {
    throw (
        "The Ruleset $operation request completed, but verification result " +
        "is unknown. Do not retry automatically; run 'protect-main.ps1 status' " +
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
    -State $verified `
    -RequiresGovernanceActivation $false
