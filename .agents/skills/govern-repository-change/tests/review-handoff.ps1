[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $skillRoot '..\..\..'))
$skillPath = Join-Path $skillRoot 'SKILL.md'
$reviewReferencePath = Join-Path $skillRoot 'references\review-handoff.md'
$rootAgentsPath = Join-Path $repositoryRoot 'AGENTS.md'
$issueTemplatePath = Join-Path $repositoryRoot '.github\ISSUE_TEMPLATE\change.yml'
$policySnapshotScript = Join-Path $skillRoot 'scripts\review-policy-snapshot.ps1'
$workflowTestPath = Join-Path $PSScriptRoot 'workflow.ps1'
$assertionCount = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertionCount++
}

function Assert-Contains {
    param([string]$Text, [string]$Fragment, [string]$Message)
    if (-not $Text.Contains($Fragment)) {
        throw "Assertion failed: $Message (missing '$Fragment')"
    }
    $script:assertionCount++
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) {
        throw "Assertion failed: $Message (expected '$Expected', actual '$Actual')"
    }
    $script:assertionCount++
}

function Assert-NotContains {
    param([string]$Text, [string]$Fragment, [string]$Message)
    if ($Text.Contains($Fragment)) {
        throw "Assertion failed: $Message (unexpected '$Fragment')"
    }
    $script:assertionCount++
}

$skillText = [IO.File]::ReadAllText($skillPath, [Text.Encoding]::UTF8)
$reviewReferenceText = [IO.File]::ReadAllText(
    $reviewReferencePath,
    [Text.Encoding]::UTF8
)
$rootAgentsText = [IO.File]::ReadAllText(
    $rootAgentsPath,
    [Text.Encoding]::UTF8
)
$issueTemplateText = [IO.File]::ReadAllText(
    $issueTemplatePath,
    [Text.Encoding]::UTF8
)
$protectedTrigger = -join @(
    [char]0x542F, [char]0x52A8, [char]0x53D7, [char]0x4FDD,
    [char]0x62A4, [char]0x8BC4, [char]0x5BA1
)

Assert-NotContains $rootAgentsText 'Custom review instructions' `
    'root policy must not depend on a nonexistent review option'
Assert-NotContains $skillText 'Custom review instructions' `
    'handoff must not depend on a nonexistent review option'
Assert-NotContains $reviewReferenceText 'Custom review instructions' `
    'review reference must not depend on a nonexistent review option'
Assert-Contains $rootAgentsText $protectedTrigger `
    'root policy names the protected review trigger'
Assert-Contains $skillText 'references/review-handoff.md' `
    'Skill routes review detail to the focused reference'
Assert-Contains $rootAgentsText 'references/review-handoff.md' `
    'root policy protects the review reference from self-authorization'
Assert-Contains $reviewReferenceText $protectedTrigger `
    'review reference names the protected review trigger'
Assert-Contains $reviewReferenceText 'scripts/review-policy-snapshot.ps1' `
    'protected review enumerates policies from both revisions'
Assert-Contains $reviewReferenceText 'exact fetched-base' `
    'candidate policy enumerator cannot authorize itself'
Assert-Contains $reviewReferenceText 'review input, never bootstrap authority' `
    'bootstrap does not trust the candidate enumerator'
Assert-Contains $reviewReferenceText 'candidate version as additive' `
    'candidate review rules remain additive'
Assert-Contains $reviewReferenceText `
    "owner's reply authorizes exactly the displayed minimum" `
    'bootstrap requires explicit owner authorization'
Assert-Contains $reviewReferenceText 'independent clone pinned' `
    'protected review uses an isolated clone'
Assert-Contains $reviewReferenceText 'remove every remote' `
    'isolated clone drops remote write paths'
Assert-NotContains $reviewReferenceText 'no remote or write credentials' `
    'handoff must not overclaim credential isolation'
Assert-Contains $reviewReferenceText 'clone-local state' `
    'handoff scopes its clone verification claim'
Assert-Contains $reviewReferenceText 'authenticated external tool' `
    'same-user reviewer is forbidden from authenticated external tools'
Assert-Contains $reviewReferenceText 'Spawn a fresh read-only reviewer subagent' `
    'protected review uses a fresh reviewer context'
Assert-Contains $reviewReferenceText 'fail closed' `
    'protected review cannot silently downgrade'
Assert-Contains $reviewReferenceText 'revision''s `references/review-handoff.md`' `
    'protected handoff reads base and candidate review references'
Assert-True ((Get-Content -LiteralPath $workflowTestPath).Count -le 500) `
    'workflow test must remain within the repository file-size limit'
Assert-True ((Get-Content -LiteralPath $PSCommandPath).Count -le 500) `
    'review handoff test must remain within the repository file-size limit'
Assert-True ((Get-Content -LiteralPath $reviewReferencePath).Count -le 500) `
    'review handoff reference must remain within the repository file-size limit'

$formElementCount = [regex]::Matches(
    $issueTemplateText,
    '(?m)^  - type:'
).Count
Assert-True ($formElementCount -le 10) `
    'Change Issue Form must contain at most ten body elements'
Assert-Contains $issueTemplateText 'id: validation_scope' `
    'Change Issue Form retains the required validation scope'

$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixtureRoot = Join-Path $tempParent (
    'swaw-review-policy-tests-' + [guid]::NewGuid().ToString('N')
)

function Invoke-FixtureGit {
    param([string[]]$Arguments)
    $output = @(& $script:git.Source -C $script:fixtureRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture git failed: $($output -join ' ')"
    }
    return $output
}

try {
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    [void](Invoke-FixtureGit @('init', '--initial-branch=main'))
    [void](Invoke-FixtureGit @('config', 'user.name', 'Review Policy Test'))
    [void](Invoke-FixtureGit @('config', 'user.email', 'review@example.invalid'))
    $unicodeDirectory = -join @([char]0x9886, [char]0x57DF)
    [void][IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'area'))
    [void][IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'Case'))
    [void][IO.Directory]::CreateDirectory((
        Join-Path $fixtureRoot $unicodeDirectory
    ))
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'AGENTS.md'), 'root policy')
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot 'area\AGENTS.md'),
        'base nested policy'
    )
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'area\value.txt'), 'base')
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot 'Case\AGENTS.md'),
        'case-sensitive base policy'
    )
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'Case\value.txt'), 'base')
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot "$unicodeDirectory\AGENTS.md"),
        'unicode policy'
    )
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot "$unicodeDirectory\value.txt"),
        'base'
    )
    [void](Invoke-FixtureGit @('add', '.'))
    [void](Invoke-FixtureGit @('commit', '-m', 'test: seed base policies'))
    $fixtureBase = [string]@(Invoke-FixtureGit @('rev-parse', 'HEAD'))[-1]

    [IO.File]::Delete((Join-Path $fixtureRoot 'area\AGENTS.md'))
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'area\value.txt'), 'head')
    [void](Invoke-FixtureGit @('mv', 'Case', 'Case-temp'))
    [void](Invoke-FixtureGit @('mv', 'Case-temp', 'case'))
    [IO.File]::WriteAllText((Join-Path $fixtureRoot 'case\value.txt'), 'head')
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot "$unicodeDirectory\value.txt"),
        'head'
    )
    [void][IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'area\deep'))
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot 'area\deep\AGENTS.md'),
        'candidate nested policy'
    )
    [IO.File]::WriteAllText(
        (Join-Path $fixtureRoot 'area\deep\value.txt'),
        'candidate'
    )
    [void](Invoke-FixtureGit @('add', '--all'))
    [void](Invoke-FixtureGit @('commit', '-m', 'test: change nested policies'))
    $fixtureHead = [string]@(Invoke-FixtureGit @('rev-parse', 'HEAD'))[-1]

    $policies = @(& $policySnapshotScript `
        -RepositoryRoot $fixtureRoot `
        -BaseSha $fixtureBase `
        -HeadSha $fixtureHead)
    Assert-Equal 6 $policies.Count 'all applicable base/head policies are listed'
    $rootPolicy = @($policies | Where-Object { $_.Path -ceq 'AGENTS.md' })[0]
    $deletedPolicy = @($policies | Where-Object {
        $_.Path -ceq 'area/AGENTS.md'
    })[0]
    $addedPolicy = @($policies | Where-Object {
        $_.Path -ceq 'area/deep/AGENTS.md'
    })[0]
    $caseBasePolicy = @($policies | Where-Object {
        $_.Path -ceq 'Case/AGENTS.md'
    })[0]
    $caseHeadPolicy = @($policies | Where-Object {
        $_.Path -ceq 'case/AGENTS.md'
    })[0]
    $unicodePolicy = @($policies | Where-Object {
        $_.Path -ceq "$unicodeDirectory/AGENTS.md"
    })[0]
    Assert-True ($rootPolicy.BaseExists -and $rootPolicy.HeadExists) `
        'root policy exists at both revisions'
    Assert-True ($deletedPolicy.BaseExists -and -not $deletedPolicy.HeadExists) `
        'deleted nested base policy remains visible'
    Assert-True (-not $addedPolicy.BaseExists -and $addedPolicy.HeadExists) `
        'new candidate policy is additive only'
    Assert-True ($caseBasePolicy.BaseExists -and -not $caseBasePolicy.HeadExists) `
        'case-only base policy path is not collapsed'
    Assert-True (-not $caseHeadPolicy.BaseExists -and $caseHeadPolicy.HeadExists) `
        'case-only candidate policy path is not collapsed'
    Assert-True ($unicodePolicy.BaseExists -and $unicodePolicy.HeadExists) `
        'non-ASCII policy path is decoded without Git quoting'
}
finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $expectedPrefix = $tempParent + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture.StartsWith(
        $expectedPrefix,
        [StringComparison]::OrdinalIgnoreCase
    ) -and [IO.Path]::GetFileName($resolvedFixture).StartsWith(
        'swaw-review-policy-tests-'
    )) {
        if ([IO.Directory]::Exists($resolvedFixture)) {
            foreach ($file in [IO.Directory]::EnumerateFiles(
                $resolvedFixture,
                '*',
                [IO.SearchOption]::AllDirectories
            )) {
                [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
            }
            [IO.Directory]::Delete($resolvedFixture, $true)
        }
    }
}

Write-Output "PASS: $assertionCount protected review contract assertions."
