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

function Get-StatusRules {
    param([Parameter(Mandatory = $true)]$Ruleset)

    return @($Ruleset.rules | Where-Object {
        $_.type -ceq 'required_status_checks'
    })
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
$productStatusRules = @(Get-StatusRules -Ruleset $productRuleset)
if ($productStatusRules.Count -ne 0) {
    throw 'Product Ruleset must not require status checks.'
}
$governanceStatusRules = @(Get-StatusRules -Ruleset $governanceRuleset)
if ($governanceStatusRules.Count -ne 1) {
    throw 'Governance Ruleset must contain one required_status_checks rule.'
}
$governanceChecks = @(
    $governanceStatusRules[0].parameters.required_status_checks
)
$contexts = @($governanceChecks | ForEach-Object { [string]$_.context })
foreach ($requiredCheck in $governanceChecks) {
    if ([long]$requiredCheck.integration_id -ne 15368) {
        throw (
            "Required check '$($requiredCheck.context)' must be bound to " +
            'the GitHub Actions integration (15368).'
        )
    }
}

if ($contexts.Count -ne 1 -or $contexts[0] -cne 'Change policy') {
    throw "Governance Ruleset must require only 'Change policy'."
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
        'Change policy must use the durable PR Issue reference after GitHub ' +
        'replaces the transient linked-branch relation.'
    )
}
if ($policyBlock -cnotmatch
    '(?s)Test-GovernanceClosingReference.*?pullRequest\.title') {
    throw 'Change policy must reject primary-Issue closing keywords in PR titles.'
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
    'Test-GovernanceIssueReference',
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

if (-not (Test-GovernanceIssueReference `
    -Body "## Link`n`nRefs: #17" `
    -IssueNumber 17)) {
    throw 'A semantic standalone Issue reference must be accepted.'
}
$nonSemanticBodies = @(
    (@('```text', 'Refs: #17', '```') -join "`n"),
    "<!--`nRefs: #17`n-->",
    "<!--`nRefs: #17",
    "    Refs: #17"
)
foreach ($nonSemanticBody in $nonSemanticBodies) {
    if (Test-GovernanceIssueReference `
        -Body $nonSemanticBody `
        -IssueNumber 17) {
        throw 'A non-semantic Issue reference must be rejected.'
    }
}
if (-not (Test-GovernanceClosingReference `
    -Body 'Fixes swawai/swaw-harness#17' `
    -IssueNumber 17 `
    -Repository 'swawai/swaw-harness')) {
    throw 'A semantic closing keyword for the primary Issue must be rejected.'
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

$validationContracts = @(
    [pscustomobject]@{
        Workflow = $productWorkflow; TriggerPath = '.github/workflows/validate.yml'
        RunnerId = 'windows-bootstrap'; AggregateId = 'product-validation'
        RunnerResult = 'needs.windows-bootstrap.result'
    },
    [pscustomobject]@{
        Workflow = $governanceWorkflow
        TriggerPath = '.github/workflows/validate-governance.yml'
        RunnerId = 'governance-suite'; AggregateId = 'governance-validation'
        RunnerResult = 'needs.governance-suite.result'
    }
)
foreach ($contract in $validationContracts) {
    $workflow = $contract.Workflow
    $trigger = [regex]::Match($workflow,
        '(?ms)^  pull_request:\s*\r?\n(?<body>.*?)(?=^  workflow_dispatch:)'
    )
    $pathBlock = [regex]::Match(
        $trigger.Groups['body'].Value,
        '(?ms)^    paths:\s*\r?\n(?<body>(?:      - .+\r?\n?)+)'
    )
    $paths = @([regex]::Matches(
        $pathBlock.Groups['body'].Value,
        '(?m)^      - (?<path>[^\r\n]+)$'
    ) | ForEach-Object { $_.Groups['path'].Value })
    if (-not $trigger.Success -or $paths.Count -ne 1 -or
        $paths[0] -cne $contract.TriggerPath) {
        throw "Full validation PR self-test must target only '$($contract.TriggerPath)'."
    }
    $inputs = @([regex]::Matches($workflow,
        '(?m)^      (?<name>pr_number|base_sha|head_sha):\s*$'
    ) | ForEach-Object { $_.Groups['name'].Value })
    if ($workflow -cnotmatch '(?m)^  workflow_dispatch:\s*$' -or
        $inputs.Count -ne 3) {
        throw 'Full validation must declare all immutable dispatch inputs.'
    }
    foreach ($inputName in @('pr_number', 'base_sha', 'head_sha')) {
        $inputPattern = '(?ms)^      ' + $inputName +
            ':\s*\r?\n(?:(?!^      \S).)*^        required:\s*true\s*$'
        if ($workflow -cnotmatch $inputPattern) {
            throw "Full validation input '$inputName' must be required."
        }
    }
    foreach ($workflowContract in @('pull-requests: read',
        'github.event.pull_request.number || inputs.pr_number'
    )) {
        if (-not $workflow.Contains($workflowContract)) {
            throw "Full validation is missing '$workflowContract'."
        }
    }

    $requestBlock = Get-WorkflowJobBlock $workflow 'validate-request'
    foreach ($requestContract in @(
        'github.actor', 'github.triggering_actor', 'github.repository_owner',
        'github.ref', 'refs/heads/main', 'github.sha',
        'inputs.pr_number', 'inputs.base_sha', 'inputs.head_sha',
        'Invoke-RestMethod', 'pullRequest.base.repo.full_name',
        'pullRequest.head.repo.full_name', 'pullRequest.base.sha',
        'pullRequest.head.sha', 'GITHUB_OUTPUT', 'pr_number=',
        'base_sha=', 'head_sha='
    )) {
        if (-not $requestBlock.Contains($requestContract)) {
            throw "Validation request is missing '$requestContract'."
        }
    }

    $runnerBlock = Get-WorkflowJobBlock $workflow $contract.RunnerId
    if ($runnerBlock -cnotmatch '(?m)^      - validate-request\s*$') {
        throw "Validation runner '$($contract.RunnerId)' must depend on its request."
    }
    $checkoutBlock = Get-WorkflowStepBlock $runnerBlock 'Check out the proposed change'
    if (-not $checkoutBlock.Contains(
        'ref: ${{ needs.validate-request.outputs.head_sha }}'
    ) -or -not $checkoutBlock.Contains('persist-credentials: false')) {
        throw 'Full validation must check out the exact credential-free PR head.'
    }
    $revisionBlock = Get-WorkflowStepBlock $runnerBlock `
        'Verify the checked-out revision'
    if (-not $revisionBlock.Contains('git rev-parse HEAD') -or
        -not $revisionBlock.Contains(
            'needs.validate-request.outputs.head_sha'
        )) {
        throw 'Full validation must verify the checked-out PR head.'
    }

    $aggregateBlock = Get-WorkflowJobBlock $workflow $contract.AggregateId
    foreach ($aggregateContract in @(
        'if: ${{ always() }}', '- validate-request',
        "- $($contract.RunnerId)", 'needs.validate-request.result',
        $contract.RunnerResult, 'needs.validate-request.outputs.pr_number',
        'REQUEST_RESULT', 'success', 'Invoke-RestMethod',
        'pullRequest.base.sha', 'pullRequest.head.sha',
        'needs.validate-request.outputs.base_sha',
        'needs.validate-request.outputs.head_sha'
    )) {
        if (-not $aggregateBlock.Contains($aggregateContract)) {
            throw "Fail-closed validation aggregate is missing '$aggregateContract'."
        }
    }
}

$windowsBlock = Get-WorkflowJobBlock $productWorkflow 'windows-bootstrap'
$productSyntaxBlock = Get-WorkflowStepBlock $windowsBlock `
    'Validate changed text and tracked syntax'
$expectedProductPathspecs = @(
    'bootstrap/**/*.ps1', 'bootstrap/**/*.psm1',
    '.github/rulesets/scripts/*.ps1', '.github/rulesets/scripts/*.psm1',
    '.github/rulesets/tests/*.ps1', '.github/rulesets/tests/*.psm1',
    '.github/rulesets/tests/**/*.ps1', '.github/rulesets/tests/**/*.psm1',
    'bootstrap/**/*.json', '.github/rulesets/protect-main.json'
)
$actualProductPathspecs = @([regex]::Matches(
    $productSyntaxBlock,
    '[''"](?<path>[^''"\r\n]+\.(?:ps1|psm1|json))[''"]'
) | ForEach-Object { $_.Groups['path'].Value })
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
    $governanceWorkflow `
    'governance-suite'
$validationSuites = @(
    [pscustomobject]@{
        Prefix = 'Exercise retained Ruleset manager under'
        Job = $windowsBlock
        Required = '.github\rulesets\tests\protect-main.ps1'
    },
    [pscustomobject]@{
        Prefix = 'Exercise governance under'
        Job = $governanceSuiteBlock
        Required = 'tests\policy.ps1'
    }
)
foreach ($suite in $validationSuites) {
    foreach ($runtime in @(
        [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Shell = 'powershell' },
        [pscustomobject]@{ Name = 'PowerShell 7'; Shell = 'pwsh' }
    )) {
        $name = "$($suite.Prefix) $($runtime.Name)"
        $block = Get-WorkflowStepBlock $suite.Job $name
        if ($block -cnotmatch (
            "(?m)^        shell: $([regex]::Escape($runtime.Shell))\s*$"
        ) -or -not $block.Contains($suite.Required) -or
            -not $block.Contains('$ErrorActionPreference = ''Stop''')) {
            throw "Validation step '$name' is incomplete."
        }
    }
}
foreach ($requiredTest in @(
    'bootstrap\windows\tests\root-build.ps1',
    'bootstrap\windows\tests\main.ps1',
    'bootstrap\windows\tests\core-rust.ps1'
)) {
    if (-not $windowsBlock.Contains($requiredTest)) {
        throw "Windows Bootstrap must exercise '$requiredTest'."
    }
}
foreach ($governanceTest in @(
    'tests\workflow.ps1', 'tests\ruleset-migration.ps1',
    'tests\lifecycle-model.ps1', 'tests\lifecycle.ps1',
    'tests\policy.ps1'
)) {
    if (-not $governanceSuiteBlock.Contains($governanceTest)) {
        throw "Governance suite must exercise '$governanceTest'."
    }
}

& (Join-Path $PSScriptRoot 'policy-runtime.ps1') `
    -RepositoryRoot $RepositoryRoot

Write-Output (
    "PASS: $($contexts.Count) required checks map to workflow jobs; " +
    'policy is base-trusted and explicit validation is fail-closed.'
)
