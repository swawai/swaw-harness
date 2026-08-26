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
$rulesetPath = Join-Path `
    $RepositoryRoot `
    '.github\rulesets\protect-main.json'
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

$productWorkflow = [IO.File]::ReadAllText(
    $productWorkflowPath,
    [Text.Encoding]::UTF8
)
$policyWorkflow = [IO.File]::ReadAllText(
    $policyWorkflowPath,
    [Text.Encoding]::UTF8
)
$governanceModule = [IO.File]::ReadAllText(
    $governanceModulePath,
    [Text.Encoding]::UTF8
)
$ruleset = [IO.File]::ReadAllText($rulesetPath, [Text.Encoding]::UTF8) |
    ConvertFrom-Json
$statusRules = @($ruleset.rules | Where-Object {
    $_.type -ceq 'required_status_checks'
})
if ($statusRules.Count -ne 1) {
    throw 'Ruleset must contain exactly one required_status_checks rule.'
}
$contexts = @(
    $statusRules[0].parameters.required_status_checks |
        ForEach-Object { [string]$_.context }
)
if ($contexts.Count -eq 0) {
    throw 'Ruleset must require at least one status check.'
}
foreach ($requiredCheck in @(
    $statusRules[0].parameters.required_status_checks
)) {
    if ([long]$requiredCheck.integration_id -ne 15368) {
        throw (
            "Required check '$($requiredCheck.context)' must be bound to " +
            'the GitHub Actions integration (15368).'
        )
    }
}

$jobNames = @(
    [regex]::Matches(
        ($productWorkflow + "`n" + $policyWorkflow),
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
if ($contexts -cnotcontains 'Change policy' -or
    $contexts -cnotcontains 'Product validation' -or
    $contexts -ccontains 'Windows Bootstrap') {
    throw (
        "Ruleset must require stable 'Change policy' and 'Product validation', " +
        "not the platform-specific 'Windows Bootstrap' job."
    )
}

$policyBlock = Get-WorkflowJobBlock `
    -Workflow $policyWorkflow `
    -JobId 'policy'
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
if ($policyBlock -cnotmatch '(?m)^          persist-credentials:\s*false\s*$') {
    throw 'Change policy checkout must not persist credentials.'
}
foreach ($eventType in @('labeled', 'unlabeled')) {
    if ($policyWorkflow -cnotmatch "(?m)^      - $eventType\s*$") {
        throw "Change policy must rerun when a PR is $eventType."
    }
}
foreach ($contract in @(
    'Get-GovernanceChangedPaths',
    'Test-GovernanceClosingReference',
    'Test-GovernanceTrustRootPath',
    'governance-migration',
    'pullRequest.user.login',
    'event.repository.owner.login'
)) {
    if (-not $policyWorkflow.Contains($contract)) {
        throw "Change policy is missing trust-root contract '$contract'."
    }
}
foreach ($trustRoot in @(
    '.github/workflows/',
    'scripts/governance.psm1',
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

$windowsBlock = Get-WorkflowJobBlock `
    -Workflow $productWorkflow `
    -JobId 'windows-bootstrap'
if ($windowsBlock -cmatch '(?m)^    needs:\s*policy\s*$') {
    throw 'Product validation must not depend on a head-controlled policy job.'
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

Write-Output (
    "PASS: $($contexts.Count) required checks map to workflow jobs; " +
    'policy is base-trusted and product aggregation is fail-closed.'
)
