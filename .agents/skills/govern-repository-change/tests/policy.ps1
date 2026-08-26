[CmdletBinding()]
param([string]$RepositoryRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$productWorkflowPath = Join-Path `
    $RepositoryRoot `
    '.github\workflows\validate.yml'
$policyWorkflowPath = Join-Path `
    $RepositoryRoot `
    '.github\workflows\change-policy.yml'
$governanceWorkflowPath = Join-Path `
    $RepositoryRoot `
    '.github\workflows\validate-governance.yml'
$productRulesetPath = Join-Path `
    $RepositoryRoot `
    '.github\rulesets\protect-main.json'
$governanceRulesetPath = Join-Path `
    $RepositoryRoot `
    '.github\rulesets\swaw-change-governance.json'
$governanceModulePath = Join-Path `
    $RepositoryRoot `
    '.agents\skills\govern-repository-change\scripts\governance.psm1'
Import-Module $governanceModulePath -Force

function Get-WorkflowJobBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Workflow,
        [Parameter(Mandatory = $true)][string]$JobId
    )

    $pattern = '(?ms)^  {0}:\s*\r?\n(?<body>.*?)(?=^  [a-z0-9-]+:\s*\r?$|\z)' -f @(
        [regex]::Escape($JobId)
    )
    $match = [regex]::Match($Workflow, $pattern)
    if (-not $match.Success) {
        throw "Workflow job '$JobId' is missing."
    }
    return $match.Groups['body'].Value
}

function Get-WorkflowStepBlock {
    param(
        [Parameter(Mandatory = $true)][string]$Job,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $pattern = (
        '(?ms)^      - name: {0}\s*\r?\n' +
        '(?<body>.*?)(?=^      - name:\s|\z)'
    ) -f @([regex]::Escape($Name))
    $match = [regex]::Match($Job, $pattern)
    if (-not $match.Success) {
        throw "Workflow step '$Name' is missing."
    }
    return $match.Groups['body'].Value
}

function Get-RequiredChecks {
    param(
        [Parameter(Mandatory = $true)]$Ruleset,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    $statusRules = @($Ruleset.rules | Where-Object {
        $_.type -ceq 'required_status_checks'
    })
    if ($statusRules.Count -ne 1) {
        throw "$Owner must contain exactly one required_status_checks rule."
    }
    $checks = @($statusRules[0].parameters.required_status_checks)
    if ($checks.Count -eq 0) {
        throw "$Owner must require at least one status check."
    }
    return $checks
}

$productWorkflow = [IO.File]::ReadAllText(
    $productWorkflowPath,
    [Text.Encoding]::UTF8
)
$policyWorkflow = [IO.File]::ReadAllText(
    $policyWorkflowPath,
    [Text.Encoding]::UTF8
)
$governanceWorkflow = [IO.File]::ReadAllText(
    $governanceWorkflowPath,
    [Text.Encoding]::UTF8
)
$governanceModule = [IO.File]::ReadAllText(
    $governanceModulePath,
    [Text.Encoding]::UTF8
)
$productRuleset = [IO.File]::ReadAllText(
    $productRulesetPath,
    [Text.Encoding]::UTF8
) | ConvertFrom-Json
$governanceRuleset = [IO.File]::ReadAllText(
    $governanceRulesetPath,
    [Text.Encoding]::UTF8
) | ConvertFrom-Json
$productChecks = @(Get-RequiredChecks `
    -Ruleset $productRuleset `
    -Owner 'Product Ruleset')
$governanceChecks = @(Get-RequiredChecks `
    -Ruleset $governanceRuleset `
    -Owner 'Governance Ruleset')
$allChecks = @($productChecks) + @($governanceChecks)
$contexts = @($allChecks | ForEach-Object { [string]$_.context })
foreach ($requiredCheck in $allChecks) {
    if ([long]$requiredCheck.integration_id -ne 15368) {
        throw (
            "Required check '$($requiredCheck.context)' must be bound to " +
            'the GitHub Actions integration (15368).'
        )
    }
}

$productContexts = @($productChecks | ForEach-Object { [string]$_.context })
if ($productContexts.Count -ne 1 -or
    $productContexts[0] -cne 'Product validation') {
    throw "Product Ruleset must require only 'Product validation'."
}
$governanceContexts = @(
    $governanceChecks | ForEach-Object { [string]$_.context }
)
if ($governanceContexts.Count -ne 2 -or
    $governanceContexts -cnotcontains 'Change policy' -or
    $governanceContexts -cnotcontains 'Governance validation') {
    throw (
        "Governance Ruleset must require 'Change policy' and " +
        "'Governance validation'."
    )
}
if (@($contexts | Sort-Object -Unique).Count -ne $contexts.Count) {
    throw 'Each required status context must have exactly one owning Ruleset.'
}

$jobNames = @(
    [regex]::Matches(
        ($productWorkflow + "`n" + $policyWorkflow + "`n" +
            $governanceWorkflow),
        '(?m)^    name:\s*(?<name>[^#\r\n]+?)\s*$'
    ) | ForEach-Object { $_.Groups['name'].Value.Trim('''', '"') }
)
foreach ($context in $contexts) {
    $matches = @($jobNames | Where-Object { $_ -ceq $context }).Count
    if ($matches -ne 1) {
        throw (
            "Required check '$context' must identify exactly one workflow job; " +
            "found $matches."
        )
    }
}

$policyBlock = Get-WorkflowJobBlock `
    -Workflow $policyWorkflow `
    -JobId 'policy'
if (-not $policyBlock.Contains(
    '^(feat|fix|refactor|test|docs|build|ci|chore)'
)) {
    throw "Change policy must accept the repository's declared commit types."
}
if ($policyWorkflow -cnotmatch '(?m)^  pull_request_target:\s*$') {
    throw 'Change policy must run from the trusted pull_request_target context.'
}
if ($policyWorkflow -cnotmatch (
    '(?m)^          ref:\s*\$\{\{\s*' +
    'github\.event\.pull_request\.base\.sha\s*\}\}\s*$'
)) {
    throw 'Change policy must check out the immutable PR base SHA.'
}
if ($policyBlock -cmatch (
    '(?m)^          ref:\s*\$\{\{\s*' +
    'github\.event\.pull_request\.head\.'
)) {
    throw 'Change policy must never check out the proposed head revision.'
}
if ($policyBlock.Contains('gh issue develop')) {
    throw (
        'Change policy must use the durable PR closing reference after GitHub ' +
        'replaces the transient linked-branch relation.'
    )
}
if ($policyBlock -cnotmatch '(?m)^          persist-credentials:\s*false\s*$') {
    throw 'Change policy checkout must not persist credentials.'
}
foreach ($eventType in @('labeled', 'unlabeled')) {
    if ($policyWorkflow -cnotmatch "(?m)^      - $eventType\s*$") {
        throw "Change policy must rerun when a PR is $eventType."
    }
}
foreach ($contract in @(
    'Get-GovernanceChecklistErrors',
    'Get-GovernanceChangedPaths',
    'Test-GovernanceClosingReference',
    'Test-GovernanceMigrationAuthorization',
    'Test-GovernanceTrustRootPath',
    'governance-migration',
    'pullRequest.user.login',
    'event.repository.owner.login',
    'event.sender.login',
    'event.action',
    'event.label.name',
    'GITHUB_RUN_ATTEMPT'
)) {
    if (-not $policyWorkflow.Contains($contract)) {
        throw "Change policy is missing trust-root contract '$contract'."
    }
}
foreach ($trustRoot in @(
    '.github/workflows/',
    'scripts/governance.psm1',
    '.github/rulesets/scripts/repository.psm1',
    'previous_filename'
)) {
    if (-not $governanceModule.Contains($trustRoot)) {
        throw "Governance module is missing trust-root contract '$trustRoot'."
    }
}

if (-not (Test-GovernanceClosingReference `
    -Body "## Link`n`nCloses #17" `
    -IssueNumber 17)) {
    throw 'A semantic standalone closing reference must be accepted.'
}
$nonSemanticBodies = @(
    (@('```text', 'Closes #17', '```') -join "`n"),
    "<!--`nCloses #17`n-->",
    "<!--`nCloses #17",
    "    Closes #17"
)
foreach ($nonSemanticBody in $nonSemanticBodies) {
    if (Test-GovernanceClosingReference `
        -Body $nonSemanticBody `
        -IssueNumber 17) {
        throw 'A non-semantic closing reference must be rejected.'
    }
}

$checklistItem = 'The reviewer confirmed the semantic checklist.'
if (@(Get-GovernanceChecklistErrors `
    -Content "   - [x] $checklistItem" `
    -Items @($checklistItem) `
    -Owner 'Test checklist').Count -ne 0) {
    throw 'A semantic checklist item indented by at most three spaces must pass.'
}
foreach ($nonSemanticChecklist in @(
    "    - [x] $checklistItem",
    (@('```text', "- [x] $checklistItem", '```') -join "`n"),
    "<!-- - [x] $checklistItem -->",
    "- [ ] $checklistItem"
)) {
    if (@(Get-GovernanceChecklistErrors `
        -Content $nonSemanticChecklist `
        -Items @($checklistItem) `
        -Owner 'Test checklist').Count -eq 0) {
        throw 'Non-semantic or incomplete checklist content must fail.'
    }
}

$renamePaths = @(Get-GovernanceChangedPaths -Files @(
    [pscustomobject]@{
        filename = 'docs/retired-policy.yml'
        previous_filename = '.github/workflows/change-policy.yml'
        status = 'renamed'
    }
))
if ($renamePaths -cnotcontains '.github/workflows/change-policy.yml' -or
    -not (@($renamePaths | Where-Object {
        Test-GovernanceTrustRootPath -Path $_
    }).Count -eq 1)) {
    throw 'Renaming a file out of a trust root must remain a trust-root change.'
}
if (@(Get-GovernanceChangedPaths -Files @()).Count -ne 0) {
    throw 'An empty final pagination page must produce no changed paths.'
}

$migrationArguments = @{
    Action = 'labeled'
    EventLabel = 'governance-migration'
    Actor = 'RepositoryOwner'
    Owner = 'repositoryowner'
    RunAttempt = 1
    RequiredLabel = 'governance-migration'
}
if (-not (Test-GovernanceMigrationAuthorization @migrationArguments)) {
    throw 'A fresh owner-applied migration label must authorize current HEAD.'
}
foreach ($staleAuthorization in @(
    @{ Action = 'synchronize' },
    @{ Action = 'edited' },
    @{ Action = 'unlabeled' },
    @{ EventLabel = '' },
    @{ EventLabel = 'unrelated-label' },
    @{ Actor = 'contributor' },
    @{ Actor = '' },
    @{ Owner = '' },
    @{ RunAttempt = 2 }
)) {
    $arguments = @{} + $migrationArguments
    foreach ($key in $staleAuthorization.Keys) {
        $arguments[$key] = $staleAuthorization[$key]
    }
    if (Test-GovernanceMigrationAuthorization @arguments) {
        throw 'Migration authorization must be fresh, exact, and owner-applied.'
    }
}

$windowsBlock = Get-WorkflowJobBlock `
    -Workflow $productWorkflow `
    -JobId 'windows-bootstrap'
if ($windowsBlock -cmatch '(?m)^    needs:\s*policy\s*$') {
    throw 'Product validation must not depend on a head-controlled policy job.'
}
$productSyntaxBlock = Get-WorkflowStepBlock `
    -Job $windowsBlock `
    -Name 'Validate changed text and tracked syntax'
$expectedProductPathspecs = @(
    'bootstrap/**/*.ps1',
    'bootstrap/**/*.psm1',
    '.github/rulesets/scripts/*.ps1',
    '.github/rulesets/scripts/*.psm1',
    '.github/rulesets/tests/*.ps1',
    '.github/rulesets/tests/*.psm1',
    '.github/rulesets/tests/**/*.ps1',
    '.github/rulesets/tests/**/*.psm1',
    'bootstrap/**/*.json',
    '.github/rulesets/protect-main.json'
)
$actualProductPathspecs = @(
    [regex]::Matches(
        $productSyntaxBlock,
        '[''"](?<path>[^''"\r\n]+\.(?:ps1|psm1|json))[''"]'
    ) | ForEach-Object { $_.Groups['path'].Value }
)
if ([regex]::Matches($productSyntaxBlock, 'git ls-files --').Count -ne 2 -or
    $actualProductPathspecs.Count -ne $expectedProductPathspecs.Count) {
    throw 'Product syntax validation must use only its two declared inventories.'
}
foreach ($pathspec in $expectedProductPathspecs) {
    if ($actualProductPathspecs -cnotcontains $pathspec) {
        throw "Product syntax validation must include '$pathspec'."
    }
}
foreach ($governanceReference in @(
    '.agents/', '.agents\', 'govern-repository-change',
    'swaw-change-governance.json'
)) {
    if ($productWorkflow.Contains($governanceReference)) {
        throw "Product validation references governance source '$governanceReference'."
    }
}
$governanceSuiteBlock = Get-WorkflowJobBlock `
    -Workflow $governanceWorkflow `
    -JobId 'governance-suite'
foreach ($runtime in @(
    [pscustomobject]@{
        Name = 'Exercise retained Ruleset manager under Windows PowerShell 5.1'
        Shell = 'powershell'
    },
    [pscustomobject]@{
        Name = 'Exercise retained Ruleset manager under PowerShell 7'
        Shell = 'pwsh'
    }
)) {
    $runtimeBlock = Get-WorkflowStepBlock `
        -Job $windowsBlock `
        -Name $runtime.Name
    if ($runtimeBlock -cnotmatch (
        "(?m)^        shell: $([regex]::Escape($runtime.Shell))\s*`$"
    ) -or -not $runtimeBlock.Contains(
        '.github\rulesets\tests\protect-main.ps1'
    ) -or -not $runtimeBlock.Contains('$ErrorActionPreference = ''Stop''')) {
        throw "Product Ruleset step '$($runtime.Name)' is incomplete."
    }
}
foreach ($runtime in @(
    [pscustomobject]@{
        Name = 'Exercise governance under Windows PowerShell 5.1'
        Shell = 'powershell'
    },
    [pscustomobject]@{
        Name = 'Exercise governance under PowerShell 7'
        Shell = 'pwsh'
    }
)) {
    $runtimeBlock = Get-WorkflowStepBlock `
        -Job $governanceSuiteBlock `
        -Name $runtime.Name
    if ($runtimeBlock -cnotmatch (
        "(?m)^        shell: $([regex]::Escape($runtime.Shell))\s*`$"
    )) {
        throw (
            "Governance step '$($runtime.Name)' must use " +
            "'$($runtime.Shell)'."
        )
    }
    if (-not $runtimeBlock.Contains('$ErrorActionPreference = ''Stop''')) {
        throw "Governance step '$($runtime.Name)' must fail fast."
    }
    foreach ($governanceTest in @(
        'tests\workflow.ps1',
        'tests\ruleset-migration.ps1',
        'tests\lifecycle-model.ps1',
        'tests\lifecycle.ps1',
        'tests\policy.ps1'
    )) {
        if (-not $runtimeBlock.Contains($governanceTest)) {
            throw (
                "Governance step '$($runtime.Name)' must exercise " +
                "'$governanceTest'."
            )
        }
    }
}
$governanceValidationBlock = Get-WorkflowJobBlock `
    -Workflow $governanceWorkflow `
    -JobId 'governance-validation'
if ($governanceValidationBlock -cnotmatch (
    '(?m)^    if:\s*\$\{\{\s*always\(\)\s*\}\}\s*$'
)) {
    throw "Governance validation must run with 'if: always()'."
}
if ($governanceValidationBlock -cnotmatch (
    '(?m)^      - governance-suite\s*$'
)) {
    throw 'Governance validation must depend on Governance suite.'
}
if (-not $governanceValidationBlock.Contains(
    'needs.governance-suite.result'
)) {
    throw 'Governance validation must inspect the Governance suite result.'
}
foreach ($requiredProductTest in @(
    'bootstrap\windows\tests\root-build.ps1',
    'bootstrap\windows\tests\main.ps1',
    'bootstrap\windows\tests\core-rust.ps1'
)) {
    if (-not $windowsBlock.Contains($requiredProductTest)) {
        throw (
            "Windows Bootstrap must exercise '$requiredProductTest'."
        )
    }
}
$productBlock = Get-WorkflowJobBlock `
    -Workflow $productWorkflow `
    -JobId 'product-validation'
if ($productBlock -cnotmatch '(?m)^    if:\s*\$\{\{\s*always\(\)\s*\}\}\s*$') {
    throw "Product validation must run with 'if: always()'."
}
if ($productBlock -cnotmatch '(?m)^      - windows-bootstrap\s*$') {
    throw 'Product validation must depend on Windows Bootstrap.'
}
if ($productBlock -cnotmatch 'needs\.windows-bootstrap\.result') {
    throw 'Product validation must inspect the Windows Bootstrap result.'
}

& (Join-Path $PSScriptRoot 'policy-runtime.ps1') `
    -RepositoryRoot $RepositoryRoot

Write-Output (
    "PASS: $($contexts.Count) required checks map to workflow jobs; " +
    'policy is base-trusted and product aggregation is fail-closed.'
)
