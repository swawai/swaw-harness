[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$startScript = Join-Path $skillRoot 'scripts\start.ps1'
$statusScript = Join-Path $skillRoot 'scripts\status.ps1'
$fakeGhswawSource = Join-Path `
    $PSScriptRoot `
    'fixtures\fake-governance-ghswaw.ps1'
$validIssueBodySource = Join-Path $PSScriptRoot 'fixtures\valid-issue.md'
$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$assertionCount = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertionCount++
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) {
        throw "Assertion failed: $Message (expected '$Expected', actual '$Actual')"
    }
    $script:assertionCount++
}

function Assert-Contains {
    param([string]$Text, [string]$Fragment, [string]$Message)
    if (-not $Text.Contains($Fragment)) {
        throw "Assertion failed: $Message (missing '$Fragment')"
    }
    $script:assertionCount++
}

function Assert-Throws {
    param([scriptblock]$Action, [string[]]$Fragments, [string]$Message)
    try { & $Action | Out-Null }
    catch {
        $text = $_.Exception.Message
        foreach ($fragment in $Fragments) {
            Assert-Contains -Text $text -Fragment $fragment `
                -Message "$Message; actual error: $text"
        }
        return $text
    }
    throw "Assertion failed: $Message (no exception was thrown)"
}

function Invoke-TestGit {
    param([string]$Root, [string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $script:git.Source -C $Root @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($exitCode -ne 0) {
        throw "Fixture git failed: $($output -join [Environment]::NewLine)"
    }
    return $output
}

function New-TestFixture {
    param([string]$Name)
    $root = Join-Path $script:testRoot $Name
    $stateRoot = Join-Path $script:testRoot ("state-$Name")
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory($stateRoot)
    [void](Invoke-TestGit $root @('init', '--initial-branch=main'))
    [void](Invoke-TestGit $root @('config', 'user.name', 'Offline Test'))
    [void](Invoke-TestGit $root @('config', 'user.email', 'offline@example.invalid'))
    [IO.File]::WriteAllText((Join-Path $root 'seed.txt'), 'seed')
    [void](Invoke-TestGit $root @('add', 'seed.txt'))
    [void](Invoke-TestGit $root @('commit', '-m', 'test: seed fixture'))
    [void](Invoke-TestGit $root @(
        'remote', 'add', 'origin',
        'https://github.com/swawai/offline-fixture.git'
    ))
    [void](Invoke-TestGit $root @(
        'update-ref', 'refs/remotes/origin/main', 'HEAD'
    ))
    return [pscustomobject]@{
        Root = $root
        Log = Join-Path $stateRoot 'fake-ghswaw.log'
        Payload = Join-Path $stateRoot 'issue-payload.json'
    }
}

function Set-FakeContext {
    param($Fixture, [string]$Scenario = 'happy')
    $env:GOVERN_FAKE_SCENARIO = $Scenario
    $env:GOVERN_FAKE_LOG = $Fixture.Log
    $env:GOVERN_FAKE_PAYLOAD = $Fixture.Payload
}

function Get-FakeCalls {
    param($Fixture)
    if (-not [IO.File]::Exists($Fixture.Log)) { return @() }
    return @([IO.File]::ReadAllLines($Fixture.Log) | Where-Object { $_ })
}

function Assert-CallCount {
    param($Fixture, [string]$Call, [int]$Expected)
    $actual = @(Get-FakeCalls $Fixture | Where-Object { $_ -ceq $Call }).Count
    Assert-Equal $Expected $actual "call count for $Call"
}

function Initialize-StatusFixture {
    param([string]$Name, [string]$Scenario)
    $fixture = New-TestFixture $Name
    [void](Invoke-TestGit $fixture.Root @('switch', '-c', 'codex/42-test-change'))
    [void](Invoke-TestGit $fixture.Root @(
        'update-ref', 'refs/remotes/origin/codex/42-test-change', 'HEAD'
    ))
    [void](Invoke-TestGit $fixture.Root @(
        'branch', '--set-upstream-to=origin/codex/42-test-change',
        'codex/42-test-change'
    ))
    @{ body = [IO.File]::ReadAllText(
        $script:validIssueBodySource,
        [Text.Encoding]::UTF8
    ) } | ConvertTo-Json |
        Set-Content -LiteralPath $fixture.Payload -Encoding UTF8
    Set-FakeContext $fixture $Scenario
    return $fixture
}

function Assert-FailClosedStatus {
    param([string]$Name, [string]$Scenario, [string]$NextActionFragment)
    $fixture = Initialize-StatusFixture $Name $Scenario
    $status = & $script:statusScript -RepositoryRoot $fixture.Root
    $diagnostic = "auth=$($status.GitHubAuthorized); error=$($status.GitHubError); " +
        "calls=$((Get-FakeCalls $fixture) -join ',')"
    Assert-Equal $false $status.GovernedContextValid `
        "$Scenario must fail closed; $diagnostic"
    Assert-True $status.NextAction.StartsWith('Stop:') "$Scenario must stop work"
    Assert-Contains $status.NextAction $NextActionFragment "$Scenario diagnostic"
    Assert-CallCount $fixture 'api-create' 0
    Assert-CallCount $fixture 'issue-develop-create' 0
}

function Assert-StatusStops {
    param($Fixture, [string]$NextActionFragment)

    $status = & $script:statusScript -RepositoryRoot $Fixture.Root
    Assert-Equal $false $status.GovernedContextValid 'status must fail closed'
    Assert-True $status.NextAction.StartsWith('Stop:') 'status must stop work'
    Assert-Contains $status.NextAction $NextActionFragment 'status diagnostic'
    return $status
}

function Move-RemoteBranchAhead {
    param($Fixture, [switch]$Diverge)

    $branch = @(Invoke-TestGit $Fixture.Root @('branch', '--show-current'))[-1]
    $remoteRef = "refs/remotes/origin/$branch"
    if ($Diverge) {
        [IO.File]::WriteAllText((Join-Path $Fixture.Root 'local.txt'), 'local')
        [void](Invoke-TestGit $Fixture.Root @('add', 'local.txt'))
        [void](Invoke-TestGit $Fixture.Root @('commit', '-m', 'test: diverge locally'))
    }
    [void](Invoke-TestGit $Fixture.Root @(
        'switch', '-c', 'fixture-remote-advance', $remoteRef
    ))
    [IO.File]::WriteAllText((Join-Path $Fixture.Root 'remote.txt'), 'remote')
    [void](Invoke-TestGit $Fixture.Root @('add', 'remote.txt'))
    [void](Invoke-TestGit $Fixture.Root @('commit', '-m', 'test: advance remote'))
    $remoteHead = @(Invoke-TestGit $Fixture.Root @('rev-parse', 'HEAD'))[-1]
    [void](Invoke-TestGit $Fixture.Root @('switch', $branch))
    [void](Invoke-TestGit $Fixture.Root @('update-ref', $remoteRef, $remoteHead))
    [void](Invoke-TestGit $Fixture.Root @('branch', '-D', 'fixture-remote-advance'))
}

$originalPath = $env:PATH
$savedEnvironment = @{}
foreach ($name in @('GOVERN_FAKE_SCENARIO', 'GOVERN_FAKE_LOG', 'GOVERN_FAKE_PAYLOAD')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempParent ('swaw-govern-tests-' + [guid]::NewGuid().ToString('N'))

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    & (Join-Path $PSScriptRoot 'review-handoff.ps1')

    $fakeBin = Join-Path $testRoot 'bin'
    [void][IO.Directory]::CreateDirectory($fakeBin)
    $fakeScript = Join-Path $fakeBin 'fake-ghswaw.ps1'
    [IO.File]::Copy($fakeGhswawSource, $fakeScript, $true)
    [IO.File]::WriteAllText(
        (Join-Path $fakeBin 'ghswaw.cmd'),
        "@echo off`r`npowershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"%~dp0fake-ghswaw.ps1`" %*`r`nexit /b %ERRORLEVEL%`r`n",
        [Text.ASCIIEncoding]::new()
    )
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $originalPath

    $happy = New-TestFixture 'happy'
    Set-FakeContext $happy
    $unicodeOutcome = 'caf' + [char]0x00E9 + ' offline change.'
    $validationScope = @(
        'Targeted checks: offline governance workflow.',
        'Important scenarios: Issue and branch identity.',
        'Known omissions: live GitHub mutations.',
        'Final full remote validation: not required.'
    ) -join "`n"
    $validationParameter = (Get-Command $startScript).Parameters['ValidationScope']
    Assert-True ($null -ne $validationParameter) 'ValidationScope parameter exists'
    $mandatory = @($validationParameter.Attributes | Where-Object {
        $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory
    })
    Assert-Equal 1 $mandatory.Count 'ValidationScope is mandatory'
    $startArguments = @{
        Title = 'Test governed change'
        Slug = 'test-change'
        Outcome = $unicodeOutcome
        Reason = 'Verify safe orchestration.'
        Scope = 'Temporary fixture.'
        NonGoals = 'Real GitHub writes.'
        Invariants = 'Remain completely offline.'
        ValidationScope = $validationScope
        AcceptanceCriteria = @('The linked branch is verified.')
        RepositoryRoot = $happy.Root
    }
    $started = & $startScript @startArguments
    Assert-Equal 'active' $started.State 'happy path state'
    Assert-Equal 'swawai/offline-fixture' $started.Repository 'origin repository identity'
    Assert-Equal 42 $started.IssueNumber 'happy path Issue number'
    Assert-Equal 'codex/42-test-change' $started.Branch 'linked branch name'
    $payload = [IO.File]::ReadAllText($happy.Payload, [Text.Encoding]::UTF8) |
        ConvertFrom-Json
    Assert-Equal 'Test governed change' $payload.title 'Issue payload title'
    Assert-Contains $payload.body $unicodeOutcome 'UTF-8 Issue body'
    Assert-Contains $payload.body '### Validation scope' 'Validation scope heading'
    Assert-Contains $payload.body $startArguments.ValidationScope `
        'Validation scope content'
    Assert-Contains $payload.body '### Acceptance criteria' 'Issue contract headings'
    Assert-CallCount $happy 'api-create' 1
    Assert-CallCount $happy 'issue-develop-create' 1
    Assert-CallCount $happy 'repo-view' 0
    $happyStatus = & $statusScript -RepositoryRoot $happy.Root
    Assert-Equal $true $happyStatus.GovernedContextValid 'happy status validity'
    Assert-Equal $true $happyStatus.LinkedBranchVerified 'linked branch verification'
    Assert-Equal 42 $happyStatus.IssueNumber 'status Issue identity'
    $trailingStatus = & $statusScript -RepositoryRoot (
        $happy.Root + [IO.Path]::DirectorySeparatorChar
    )
    Assert-Equal $true $trailingStatus.GovernedContextValid `
        'trailing separator status root'

    $runtime = (Get-Process -Id $PID).Path
    $freshCode = "`$status = & '$($statusScript.Replace("'", "''"))' " +
        "-RepositoryRoot '$($happy.Root.Replace("'", "''"))'; " +
        "if (-not `$status.GovernedContextValid) { throw 'fresh status failed' }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($freshCode))
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $runtime -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>&1 |
        Out-Null
    $freshExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    Assert-Equal 0 $freshExitCode 'fresh-process status invocation'

    $whatIf = New-TestFixture 'whatif'
    Set-FakeContext $whatIf
    $startArguments.RepositoryRoot = $whatIf.Root + [IO.Path]::DirectorySeparatorChar
    $planned = & $startScript @startArguments -WhatIf
    Assert-Equal 'planned' $planned.State 'WhatIf state'
    $whatIfBranch = @(Invoke-TestGit $whatIf.Root @('branch', '--show-current'))
    Assert-Equal 'main' $whatIfBranch[-1] 'WhatIf branch'
    Assert-CallCount $whatIf 'api-create' 0
    Assert-CallCount $whatIf 'issue-develop-create' 0
    Assert-Equal $false ([IO.File]::Exists($whatIf.Payload)) 'WhatIf payload write'

    foreach ($case in @(
        @{ Name = 'unclosed-comment'; Outcome = '<!--' },
        @{ Name = 'unclosed-fence'; Outcome = '```text' }
    )) {
        $malformed = New-TestFixture $case.Name
        Set-FakeContext $malformed
        $malformedArguments = @{} + $startArguments
        $malformedArguments.RepositoryRoot = $malformed.Root
        $malformedArguments.Outcome = $case.Outcome
        [void](Assert-Throws {
            & $startScript @malformedArguments -WhatIf
        } @('Generated Issue does not satisfy', 'Issue section') $case.Name)
        Assert-CallCount $malformed 'api-create' 0
        Assert-CallCount $malformed 'issue-develop-create' 0
    }

    $dirty = New-TestFixture 'dirty'
    [IO.File]::WriteAllText((Join-Path $dirty.Root 'dirty.txt'), 'dirty')
    Set-FakeContext $dirty
    $startArguments.RepositoryRoot = $dirty.Root
    [void](Assert-Throws { & $startScript @startArguments } @('clean worktree') 'dirty preflight')
    Assert-CallCount $dirty 'doctor' 0
    Assert-CallCount $dirty 'api-create' 0

    Assert-FailClosedStatus 'closed' 'closed' 'not open'
    Assert-FailClosedStatus 'missing' 'missing' 'could not be read'
    Assert-FailClosedStatus 'malformed' 'malformed' 'change contract'
    Assert-FailClosedStatus 'heading-suffix' 'heading-suffix' 'change contract'
    Assert-FailClosedStatus 'commented' 'commented-contract' 'change contract'
    Assert-FailClosedStatus 'fenced' 'fenced-contract' 'change contract'
    Assert-FailClosedStatus 'higher-heading' 'higher-heading-boundary' 'change contract'
    Assert-FailClosedStatus 'lowercase-heading' 'lowercase-heading' 'change contract'
    Assert-FailClosedStatus `
        'indented-readiness' `
        'indented-readiness' `
        'change contract'
    Assert-FailClosedStatus 'unlinked' 'unlinked' 'Issue-linked branch'
    Assert-FailClosedStatus 'open-pr-no-reference' 'open-pr-no-reference' `
        'standalone Refs: #42'
    Assert-FailClosedStatus 'open-pr-closing' 'open-pr-closing' `
        'must not close, fix, or resolve'
    Assert-FailClosedStatus 'wrong-link' 'wrong-linked-repo' 'Issue-linked branch'
    Assert-FailClosedStatus 'pr-failure' 'pr-failure' 'pull request state'
    Assert-FailClosedStatus 'wrong-pr-repo' 'wrong-pr-repo' 'pull request state'
    Assert-FailClosedStatus 'wrong-pr-base' 'wrong-pr-base' 'pull request state'
    Assert-FailClosedStatus 'wrong-pr-head' 'wrong-pr-head' 'pull request state'
    Assert-FailClosedStatus 'auth' 'auth-failure' 'could not be verified'
    Assert-FailClosedStatus `
        'stale-remote' `
        'remote-ahead-unfetched' `
        'remote-tracking branch is stale'
    Assert-FailClosedStatus `
        'remote-ref-failure' `
        'remote-ref-failure' `
        'remote branch state'

    $openPullRequest = Initialize-StatusFixture 'open-pr' 'open-pr'
    $openPullRequestStatus = & $statusScript -RepositoryRoot $openPullRequest.Root
    Assert-Equal $true $openPullRequestStatus.GovernedContextValid `
        'matching open PR status'
    Assert-Equal $false $openPullRequestStatus.LinkedBranchVerified `
        'matching PR replaces the transient linked-branch relation'
    Assert-Equal $true $openPullRequestStatus.PullRequestIssueLinkVerified `
        'matching PR Issue reference'
    Assert-Equal $true $openPullRequestStatus.IssueChangeLinkVerified `
        'matching PR preserves the durable Issue relation'
    Assert-Equal 1 @($openPullRequestStatus.PullRequests).Count `
        'matching open PR discovery'
    Assert-Contains $openPullRequestStatus.NextAction `
        'Inspect the open PR' `
        'matching open PR next action'
    [IO.File]::WriteAllText(
        (Join-Path $openPullRequest.Root 'review-fix.txt'),
        'review fix'
    )
    [void](Invoke-TestGit $openPullRequest.Root @('add', 'review-fix.txt'))
    [void](Invoke-TestGit $openPullRequest.Root @(
        'commit', '-m', 'test: prepare PR update'
    ))
    $openPullRequestUpdate = & $statusScript -RepositoryRoot $openPullRequest.Root
    Assert-Contains $openPullRequestUpdate.NextAction `
        'Push the verified commits' `
        'open PR update next action'

    $automaticPush = Initialize-StatusFixture 'automatic-push' 'happy'
    [IO.File]::WriteAllText((Join-Path $automaticPush.Root 'change.txt'), 'change')
    [void](Invoke-TestGit $automaticPush.Root @('add', 'change.txt'))
    [void](Invoke-TestGit $automaticPush.Root @(
        'commit', '-m', 'test: prepare automatic push'
    ))
    $automaticPushStatus = & $statusScript -RepositoryRoot $automaticPush.Root
    Assert-Equal $true $automaticPushStatus.GovernedContextValid `
        'automatic push status validity'
    Assert-Contains $automaticPushStatus.NextAction `
        'Push the verified commits' `
        'automatic push next action'

    $published = Initialize-StatusFixture 'published' 'happy'
    [IO.File]::WriteAllText((Join-Path $published.Root 'published.txt'), 'published')
    [void](Invoke-TestGit $published.Root @('add', 'published.txt'))
    [void](Invoke-TestGit $published.Root @(
        'commit', '-m', 'test: publish fixture change'
    ))
    [void](Invoke-TestGit $published.Root @(
        'update-ref',
        'refs/remotes/origin/codex/42-test-change',
        'HEAD'
    ))
    $publishedStatus = & $statusScript -RepositoryRoot $published.Root
    Assert-Equal $true $publishedStatus.GovernedContextValid `
        'published status validity'
    Assert-Contains $publishedStatus.NextAction `
        'Open a Draft PR' `
        'published branch next action'

    $noUpstream = Initialize-StatusFixture 'no-upstream' 'happy'
    [void](Invoke-TestGit $noUpstream.Root @('branch', '--unset-upstream'))
    [void](Assert-StatusStops $noUpstream 'must track')

    $wrongUpstream = Initialize-StatusFixture 'wrong-upstream' 'happy'
    [void](Invoke-TestGit $wrongUpstream.Root @(
        'update-ref', 'refs/remotes/origin/other', 'HEAD'
    ))
    [void](Invoke-TestGit $wrongUpstream.Root @(
        'branch', '--set-upstream-to=origin/other'
    ))
    [void](Assert-StatusStops $wrongUpstream 'must track')

    $missingRemote = Initialize-StatusFixture 'missing-remote' 'happy'
    [void](Invoke-TestGit $missingRemote.Root @(
        'update-ref', '-d', 'refs/remotes/origin/codex/42-test-change'
    ))
    [void](Assert-StatusStops $missingRemote 'remote-tracking branch is missing')

    $behind = Initialize-StatusFixture 'behind-upstream' 'happy'
    Move-RemoteBranchAhead $behind
    [void](Assert-StatusStops $behind 'behind or diverged')

    $diverged = Initialize-StatusFixture 'diverged-upstream' 'happy'
    Move-RemoteBranchAhead $diverged -Diverge
    [void](Assert-StatusStops $diverged 'behind or diverged')

    $pushMismatch = Initialize-StatusFixture 'push-mismatch' 'happy'
    [void](Invoke-TestGit $pushMismatch.Root @(
        'remote', 'set-url', '--push', 'origin',
        'https://github.com/other/offline-fixture.git'
    ))
    $pushMismatchStatus = Assert-StatusStops $pushMismatch 'could not be verified'
    Assert-Contains $pushMismatchStatus.GitHubError `
        'must identify one repository' `
        'push URL repository identity'

    $bareOrigin = New-TestFixture 'bare-origin'
    [void](Invoke-TestGit $bareOrigin.Root @(
        'remote', 'set-url', 'origin', 'swawai/offline-fixture'
    ))
    Set-FakeContext $bareOrigin
    $startArguments.RepositoryRoot = $bareOrigin.Root
    [void](Assert-Throws { & $startScript @startArguments } @(
        'not an explicit github.com repository URL'
    ) 'bare origin rejection')
    Assert-CallCount $bareOrigin 'doctor' 0

    $credentialOrigin = New-TestFixture 'credential-origin'
    [void](Invoke-TestGit $credentialOrigin.Root @(
        'remote', 'set-url', 'origin',
        'https://user:do-not-log@github.com/swawai/offline-fixture.git'
    ))
    Set-FakeContext $credentialOrigin
    $startArguments.RepositoryRoot = $credentialOrigin.Root
    $credentialError = Assert-Throws { & $startScript @startArguments } @(
        'not an explicit github.com repository URL'
    ) 'credential origin rejection'
    Assert-True (-not $credentialError.Contains('do-not-log')) `
        'origin diagnostics must redact credentials'
    Assert-CallCount $credentialOrigin 'doctor' 0

    $branchFailure = New-TestFixture 'branch-failure'
    Set-FakeContext $branchFailure 'branch-failure'
    $startArguments.RepositoryRoot = $branchFailure.Root
    [void](Assert-Throws { & $startScript @startArguments } @(
        'Issue #42 was created', 'Do not create another Issue or retry blindly'
    ) 'partial Issue recovery warning')
    Assert-CallCount $branchFailure 'api-create' 1
    Assert-CallCount $branchFailure 'issue-develop-create' 1
    $remainingBranch = @(Invoke-TestGit $branchFailure.Root @('branch', '--show-current'))
    Assert-Equal 'main' $remainingBranch[-1] 'failed branch checkout'

    $uncertain = New-TestFixture 'issue-uncertain'
    Set-FakeContext $uncertain 'issue-uncertain'
    $startArguments.RepositoryRoot = $uncertain.Root
    [void](Assert-Throws { & $startScript @startArguments } @(
        'Issue creation result is unknown', 'Do not retry automatically'
    ) 'uncertain Issue result warning')
    Assert-CallCount $uncertain 'api-create' 1
    Assert-CallCount $uncertain 'issue-develop-create' 0

    Write-Output "PASS: $assertionCount assertions; all GitHub behavior was simulated offline."
}
finally {
    $env:PATH = $originalPath
    foreach ($name in $savedEnvironment.Keys) {
        $value = $savedEnvironment[$name]
        if ($null -eq $value) { Remove-Item "Env:$name" -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $value, 'Process') }
    }
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $expectedPrefix = $tempParent + [IO.Path]::DirectorySeparatorChar
    if ($resolvedRoot.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedRoot).StartsWith('swaw-govern-tests-')) {
        if ([IO.Directory]::Exists($resolvedRoot)) {
            foreach ($file in [IO.Directory]::EnumerateFiles(
                $resolvedRoot,
                '*',
                [IO.SearchOption]::AllDirectories
            )) {
                [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
            }
            [IO.Directory]::Delete($resolvedRoot, $true)
        }
    }
}
