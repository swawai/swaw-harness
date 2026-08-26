[CmdletBinding()]
param([string]$RepositoryRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$workflowPath = Join-Path `
    $RepositoryRoot `
    '.github\workflows\change-policy.yml'
$modulePath = Join-Path `
    $RepositoryRoot `
    '.agents\skills\govern-repository-change\scripts\governance.psm1'
$workflow = [IO.File]::ReadAllText($workflowPath, [Text.Encoding]::UTF8)
Import-Module $modulePath -Force
$assertionCount = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
    $script:assertionCount++
}

foreach ($contract in @(
    '\$files\s*=\s*@\(\$fileResponse\s*\|\s*ForEach-Object\s*\{\s*\$_\s*\}\)',
    '\$commits\s*=\s*@\(\$commitResponse\s*\|\s*ForEach-Object\s*\{\s*\$_\s*\}\)'
)) {
    Assert-True ([regex]::IsMatch($workflow, $contract)) `
        'each paginated GitHub API collection is explicitly enumerated'
}
Assert-True $workflow.Contains(
    "issue.PSObject.Properties['pull_request']"
) 'the optional Issue pull_request property is inspected safely'

function Get-TestApiItems {
    param([AllowNull()]$Response)
    return @($Response | ForEach-Object { $_ })
}

$multiResponse = Write-Output -NoEnumerate ([object[]]@(
    [pscustomobject]@{ id = 1 },
    [pscustomobject]@{ id = 2 }
))
$multiItems = @(Get-TestApiItems -Response $multiResponse)
Assert-True ($multiItems.Count -eq 2) `
    'a non-enumerated multi-item API response retains cardinality'
Assert-True (
    [int]$multiItems[0].id -eq 1 -and [int]$multiItems[1].id -eq 2
) 'a multi-item API response retains item identity and order'
Assert-True (@(Get-TestApiItems -Response ([object[]]@())).Count -eq 0) `
    'an empty API page remains empty'
Assert-True (@(Get-TestApiItems `
    -Response ([pscustomobject]@{ id = 1 })).Count -eq 1) `
    'a singleton API response remains a singleton'

$ordinaryIssue = [pscustomobject]@{ state = 'open' }
$pullRequestIssue = [pscustomobject]@{
    state = 'open'
    pull_request = [pscustomobject]@{ url = 'https://example.invalid/pr' }
}
Assert-True ($null -eq $ordinaryIssue.PSObject.Properties['pull_request']) `
    'an ordinary Issue may omit pull_request under StrictMode'
Assert-True ($null -ne $pullRequestIssue.PSObject.Properties['pull_request']) `
    'a PR-shaped Issue exposes pull_request under StrictMode'

$terminalTSection = @(
    '## Author checklist',
    '',
    '- [x] A terminal-t heading remains addressable.'
) -join "`r`n"
$section = Get-GovernanceMarkdownSection `
    -Body $terminalTSection `
    -Heading 'Author checklist' `
    -Level 2
Assert-True (
    $section -ceq '- [x] A terminal-t heading remains addressable.'
) 'a CRLF heading ending in t remains exact'

$checklistItem = 'The reviewer confirmed the semantic checklist.'
$tab = [string][char]9
$validTabbedChecklist = "-$tab[x]$tab$checklistItem$tab"
Assert-True (@(Get-GovernanceChecklistErrors `
    -Content $validTabbedChecklist `
    -Items @($checklistItem) `
    -Owner 'Test checklist').Count -eq 0) `
    'an actual tab remains valid Markdown whitespace'
Assert-True (@(Get-GovernanceChecklistErrors `
    -Content "-t[x]t$checklistItem" `
    -Items @($checklistItem) `
    -Owner 'Test checklist').Count -gt 0) `
    'the literal letter t is not treated as whitespace'
$literalTUnchecked = @(
    $validTabbedChecklist,
    '-t[t]tThis is not a Markdown task.'
) -join "`n"
Assert-True (@(Get-GovernanceChecklistErrors `
    -Content $literalTUnchecked `
    -Items @($checklistItem) `
    -Owner 'Test checklist').Count -eq 0) `
    'literal t cannot manufacture an incomplete checklist item'
$actualTabUnchecked = @(
    $validTabbedChecklist,
    "-$tab[ ]$tab This task is incomplete."
) -join "`n"
Assert-True (@(Get-GovernanceChecklistErrors `
    -Content $actualTabUnchecked `
    -Items @($checklistItem) `
    -Owner 'Test checklist').Count -eq 1) `
    'actual tab whitespace preserves incomplete task detection'
Assert-True (-not (Test-GovernanceClosingReference `
    -Body 'Closet#17' `
    -IssueNumber 17)) 'literal t cannot separate Closes from an Issue number'
Assert-True (-not (Test-GovernanceClosingReference `
    -Body 'Closes #17t' `
    -IssueNumber 17)) 'literal t cannot trail an Issue number'

Write-Output "PASS: $assertionCount policy runtime assertions."
