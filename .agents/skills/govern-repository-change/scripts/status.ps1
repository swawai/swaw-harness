[CmdletBinding()]
param([string]$RepositoryRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$baseBranch = 'main'
Import-Module (Join-Path $PSScriptRoot 'governance.psm1') -Force

function Get-PullRequestHeadRepositoryName {
    param([Parameter(Mandatory = $true)]$PullRequest)

    $headRepositoryProperty = $PullRequest.PSObject.Properties['headRepository']
    if ($null -eq $headRepositoryProperty) {
        return $null
    }
    $headRepository = $headRepositoryProperty.Value
    if ($headRepository -is [string]) {
        return [string]$headRepository
    }
    if ($null -ne $headRepository) {
        foreach ($property in @('nameWithOwner', 'fullName', 'full_name')) {
            $candidate = $headRepository.PSObject.Properties[$property]
            if ($null -ne $candidate -and
                -not [string]::IsNullOrWhiteSpace([string]$candidate.Value)) {
                return [string]$candidate.Value
            }
        }
        $nameProperty = $headRepository.PSObject.Properties['name']
        $ownerProperty = $PullRequest.PSObject.Properties['headRepositoryOwner']
        if ($null -ne $nameProperty -and
            $null -ne $ownerProperty -and
            $null -ne $ownerProperty.Value) {
            $loginProperty = $ownerProperty.Value.PSObject.Properties['login']
            if ($null -ne $loginProperty) {
                return "$($loginProperty.Value)/$($nameProperty.Value)"
            }
        }
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$RepositoryRoot = Get-GovernanceNormalizedPath -Path $RepositoryRoot
$git = Get-Command git -CommandType Application -ErrorAction Stop |
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

Push-Location -LiteralPath $RepositoryRoot
try {
    $branchOutput = @(Invoke-GovernanceCommand `
        -Executable $git.Source `
        -Arguments @('branch', '--show-current') `
        -Operation 'Read current branch')
    $branch = $branchOutput[-1].Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $branch = '(detached)'
    }
    $headOutput = @(Invoke-GovernanceCommand `
        -Executable $git.Source `
        -Arguments @('rev-parse', 'HEAD') `
        -Operation 'Read HEAD')
    $head = $headOutput[-1].Trim()
    $worktree = @(Invoke-GovernanceCommand `
        -Executable $git.Source `
        -Arguments @('status', '--porcelain=v1', '--untracked-files=all') `
        -Operation 'Inspect worktree')
    $origin = $null
    $originError = $null
    try {
        $origin = Get-GovernanceOrigin `
            -Git $git.Source `
            -RepositoryRoot $RepositoryRoot
    }
    catch {
        $originError = $_.Exception.Message
    }
    $repository = if ($null -ne $origin) { $origin.Repository } else { $null }
    $originUrl = if ($null -ne $origin) { $origin.FetchUrls[0] } else { $null }

    $ahead = $null
    $behind = $null
    $baseRefResult = Invoke-GovernanceNative `
        -Executable $git.Source `
        -Arguments @(
            'show-ref', '--verify', '--quiet',
            "refs/remotes/origin/$baseBranch"
        )
    if ($baseRefResult.ExitCode -eq 0) {
        $countOutput = @(Invoke-GovernanceCommand `
            -Executable $git.Source `
            -Arguments @(
                'rev-list', '--left-right', '--count',
                "refs/remotes/origin/$baseBranch...HEAD"
            ) `
            -Operation 'Compare with base branch')
        $counts = $countOutput[-1] -split '\s+'
        if ($counts.Count -eq 2) {
            $behind = [int]$counts[0]
            $ahead = [int]$counts[1]
        }
    }

    $tracking = Get-GovernanceBranchTracking `
        -Git $git.Source `
        -RepositoryRoot $RepositoryRoot `
        -Branch $branch
    $upstream = $tracking.Upstream
    $aheadOfUpstream = $tracking.Ahead
    $behindUpstream = $tracking.Behind

    $branchMatch = [regex]::Match(
        $branch,
        '^[a-z][a-z0-9-]*/(?<issue>[1-9][0-9]*)-[a-z0-9]+(?:-[a-z0-9]+)*$'
    )
    $issueNumber = if ($branchMatch.Success) {
        [int]$branchMatch.Groups['issue'].Value
    }
    else {
        $null
    }
    $expectedUpstream = if ($branchMatch.Success) {
        "origin/$branch"
    }
    else {
        $null
    }
    $remoteBranchRefExists = $false
    $remoteTrackingOid = $null
    if ($branchMatch.Success) {
        $remoteBranchRefResult = Invoke-GovernanceNative `
            -Executable $git.Source `
            -Arguments @(
                'show-ref', '--verify', '--quiet',
                "refs/remotes/origin/$branch"
            )
        $remoteBranchRefExists = $remoteBranchRefResult.ExitCode -eq 0
        if ($remoteBranchRefExists) {
            $remoteTrackingOutput = @(Invoke-GovernanceCommand `
                -Executable $git.Source `
                -Arguments @('rev-parse', "refs/remotes/origin/$branch") `
                -Operation 'Read remote-tracking branch')
            $remoteTrackingOid = $remoteTrackingOutput[-1].Trim()
        }
    }
    $upstreamIsExpected = $branchMatch.Success -and
        [string]$upstream -ceq $expectedUpstream
    $upstreamReady = $upstreamIsExpected -and
        $remoteBranchRefExists -and
        $null -ne $behindUpstream -and
        $behindUpstream -eq 0

    $githubAuthorized = $false
    $githubError = $null
    $issue = $null
    $issueContractErrors = @()
    $linkedBranchVerified = $false
    $linkedBranchError = $null
    $pullRequestIssueLinkVerified = $pullRequestClosingReferenceDetected = $false
    $issueChangeLinkVerified = $false
    $remoteBranchOid = $null
    $remoteBranchError = $null
    $remoteBranchMatchesTracking = $false
    $pullRequests = @()
    $pullRequestQueryVerified = $false
    $ghswaw = Get-Command ghswaw `
        -CommandType Application `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $ghswaw) {
        $githubError = 'ghswaw is not available.'
    }
    elseif ($null -ne $originError) {
        $githubError = $originError
    }
    else {
        $doctorResult = Invoke-GovernanceNative `
            -Executable $ghswaw.Source `
            -Arguments @('.doctor')
        if ($doctorResult.ExitCode -ne 0) {
            $doctorOutput = @($doctorResult.Output)
            $githubError = (@($doctorOutput | ForEach-Object {
                [string]$_
            }) -join "`n").Trim()
        }
        else {
            $githubAuthorized = $true
            if ($null -ne $issueNumber) {
                $remoteBranchResult = Invoke-GovernanceNative `
                    -Executable $ghswaw.Source `
                    -Arguments @(
                        'api', '--method', 'GET',
                        "repos/$repository/git/ref/heads/$branch"
                    )
                $remoteBranchOutput = @($remoteBranchResult.Output)
                if ($remoteBranchResult.ExitCode -eq 0) {
                    try {
                        $remoteBranch = ($remoteBranchOutput -join "`n") |
                            ConvertFrom-Json
                        $remoteBranchOid = [string]$remoteBranch.object.sha
                        if ([string]::IsNullOrWhiteSpace($remoteBranchOid)) {
                            throw 'GitHub ref response did not contain object.sha.'
                        }
                        $remoteBranchMatchesTracking = [string]::Equals(
                            $remoteBranchOid,
                            $remoteTrackingOid,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    }
                    catch {
                        $remoteBranchError = $_.Exception.Message
                    }
                }
                else {
                    $remoteBranchError = (@($remoteBranchOutput | ForEach-Object {
                        [string]$_
                    }) -join "`n").Trim()
                }
                if (-not [string]::IsNullOrWhiteSpace($remoteBranchError)) {
                    $githubError = $remoteBranchError
                }

                $issueResult = Invoke-GovernanceNative `
                    -Executable $ghswaw.Source `
                    -Arguments @(
                        'issue', 'view', [string]$issueNumber,
                        '--repo', $repository,
                        '--json', 'number,title,state,url,body'
                    )
                $issueOutput = @($issueResult.Output)
                if ($issueResult.ExitCode -eq 0) {
                    $issue = ($issueOutput -join "`n") | ConvertFrom-Json
                    $issueContractErrors = @(Test-GovernanceIssueContract `
                        -Body ([string]$issue.body))

                    $linkedResult = Invoke-GovernanceNative `
                        -Executable $ghswaw.Source `
                        -Arguments @(
                            'issue', 'develop', '--list',
                            [string]$issueNumber,
                            '--repo', $repository
                        )
                    $linkedOutput = @($linkedResult.Output)
                    if ($linkedResult.ExitCode -eq 0) {
                        $linkedBranchVerified = Test-GovernanceLinkedBranch `
                            -Output $linkedOutput `
                            -Repository $repository `
                            -Branch $branch
                    }
                    else {
                        $linkedBranchError = (@($linkedOutput | ForEach-Object {
                            [string]$_
                        }) -join "`n").Trim()
                    }
                }
                else {
                    $githubError = (@($issueOutput | ForEach-Object {
                        [string]$_
                    }) -join "`n").Trim()
                }
            }

            $prResult = Invoke-GovernanceNative `
                -Executable $ghswaw.Source `
                -Arguments @(
                    'pr', 'list',
                    '--repo', $repository,
                    '--head', $branch,
                    '--base', $baseBranch,
                    '--state', 'all',
                    '--limit', '10',
                    '--json',
                    ('number,title,state,isDraft,url,mergeStateStatus,' +
                        'statusCheckRollup,headRefName,headRepository,' +
                        'headRepositoryOwner,baseRefName,body')
                )
            $prOutput = @($prResult.Output)
            if ($prResult.ExitCode -eq 0) {
                $parsedPullRequests = ($prOutput -join "`n") |
                    ConvertFrom-Json
                $pullRequestList = [Collections.Generic.List[object]]::new()
                $pullRequestIdentityErrors = [Collections.Generic.List[string]]::new()
                foreach ($pullRequest in $parsedPullRequests) {
                    if ($null -ne $pullRequest) {
                        $headRepository = Get-PullRequestHeadRepositoryName `
                            -PullRequest $pullRequest
                        if ([string]$pullRequest.headRefName -cne $branch -or
                            [string]$pullRequest.baseRefName -cne $baseBranch -or
                            -not [string]::Equals(
                                $headRepository,
                                $repository,
                                [StringComparison]::OrdinalIgnoreCase
                            )) {
                            [void]$pullRequestIdentityErrors.Add(
                                "PR #$($pullRequest.number) does not match " +
                                "${repository}:$branch -> $baseBranch."
                            )
                        }
                        else {
                            [void]$pullRequestList.Add($pullRequest)
                        }
                    }
                }
                $pullRequests = $pullRequestList.ToArray()
                if ($pullRequestIdentityErrors.Count -eq 0) {
                    $pullRequestQueryVerified = $true
                }
                else {
                    $githubError = $pullRequestIdentityErrors -join ' '
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($githubError)) {
                $githubError = (@($prOutput | ForEach-Object {
                    [string]$_
                }) -join "`n").Trim()
            }
        }
    }

    $isClean = $worktree.Count -eq 0
    $openPullRequest = @($pullRequests | Where-Object {
        [string]$_.state -eq 'OPEN'
    } | Select-Object -First 1)
    if ($null -ne $issueNumber -and $openPullRequest.Count -eq 1) {
        $pullRequestIssueLinkVerified = Test-GovernanceIssueReference `
            -Body ([string]$openPullRequest[0].body) `
            -IssueNumber $issueNumber
        $pullRequestClosingReferenceDetected = Test-GovernanceClosingReference `
            -Body (([string]$openPullRequest[0].title) + "`n" +
                ([string]$openPullRequest[0].body)) `
            -IssueNumber $issueNumber `
            -Repository $repository
        $pullRequestIssueLinkVerified = $pullRequestIssueLinkVerified -and
            -not $pullRequestClosingReferenceDetected
    }
    $issueChangeLinkVerified = $pullRequestIssueLinkVerified
    if ($openPullRequest.Count -eq 0) {
        $issueChangeLinkVerified = $linkedBranchVerified
    }
    $issueIsOpen = $null -ne $issue -and [string]$issue.state -ceq 'OPEN'
    $governedContextValid = (
        $branchMatch.Success -and
        $githubAuthorized -and
        $issueIsOpen -and
        $issueContractErrors.Count -eq 0 -and
        $issueChangeLinkVerified -and
        $remoteBranchMatchesTracking -and
        $upstreamReady -and
        $pullRequestQueryVerified
    )
    if ($branch -ceq $baseBranch) {
        $nextAction = if ($isClean) {
            'Start a governed change before changing version-controlled content.'
        }
        else {
            'Stop: the base branch has uncommitted work.'
        }
    }
    elseif (-not $branchMatch.Success) {
        $nextAction = 'Stop: the branch does not identify a governed Issue.'
    }
    elseif (-not $githubAuthorized) {
        $nextAction = 'Stop: GitHub governance state could not be verified.'
    }
    elseif ($null -eq $issue) {
        $nextAction = 'Stop: the branch Issue could not be read.'
    }
    elseif (-not $issueIsOpen) {
        $nextAction = 'Stop: the branch Issue is not open.'
    }
    elseif ($issueContractErrors.Count -gt 0) {
        $nextAction = 'Stop: the branch Issue does not satisfy the change contract.'
    }
    elseif ($pullRequestClosingReferenceDetected) {
        $nextAction = (
            "Stop: the open PR title and body must not close, fix, or resolve " +
            "primary Issue #$issueNumber."
        )
    }
    elseif ($openPullRequest.Count -eq 1 -and
        -not $pullRequestIssueLinkVerified) {
        $nextAction = (
            "Stop: the open PR must contain a standalone Refs: #$issueNumber " +
            'reference.'
        )
    }
    elseif ($openPullRequest.Count -eq 0 -and
        -not $linkedBranchVerified -and
        -not [string]::IsNullOrWhiteSpace($linkedBranchError)) {
        $nextAction = 'Stop: the Issue-linked branch relation could not be verified.'
    }
    elseif ($openPullRequest.Count -eq 0 -and -not $linkedBranchVerified) {
        $nextAction = 'Stop: GitHub does not identify this as an Issue-linked branch.'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($remoteBranchError)) {
        $nextAction = 'Stop: the remote branch state could not be verified.'
    }
    elseif (-not $upstreamIsExpected) {
        $nextAction = "Stop: the branch must track '$expectedUpstream'."
    }
    elseif (-not $remoteBranchRefExists) {
        $nextAction = 'Stop: the Issue-linked remote-tracking branch is missing.'
    }
    elseif (-not $remoteBranchMatchesTracking) {
        $nextAction = 'Stop: the remote-tracking branch is stale; fetch before continuing.'
    }
    elseif ($null -eq $behindUpstream) {
        $nextAction = 'Stop: upstream synchronization could not be measured.'
    }
    elseif ($behindUpstream -gt 0) {
        $nextAction = 'Stop: the branch is behind or diverged from its upstream.'
    }
    elseif (-not $pullRequestQueryVerified) {
        $nextAction = 'Stop: pull request state could not be verified.'
    }
    elseif ($openPullRequest.Count -gt 0 -and -not $isClean) {
        $nextAction = 'Continue the bounded implementation; an open PR already exists.'
    }
    elseif ($openPullRequest.Count -gt 0 -and
        $null -ne $aheadOfUpstream -and $aheadOfUpstream -gt 0) {
        $nextAction = 'Push the verified commits to update the open PR; never force-push.'
    }
    elseif ($openPullRequest.Count -gt 0) {
        $nextAction = 'Inspect the open PR and its required checks; never merge as Agent.'
    }
    elseif (-not $isClean) {
        $nextAction = 'Continue the bounded implementation and verification.'
    }
    elseif ($null -ne $aheadOfUpstream -and $aheadOfUpstream -gt 0) {
        $nextAction = 'Push the verified commits to the Issue-linked branch without force.'
    }
    elseif ($null -ne $ahead -and $ahead -gt 0) {
        $nextAction = 'Open a Draft PR for the published Issue-linked branch.'
    }
    else {
        $nextAction = 'No uncommitted or unmerged change is visible locally.'
    }

    [pscustomobject][ordered]@{
        RepositoryRoot = $RepositoryRoot
        Repository = $repository
        Origin = $originUrl
        OriginFetchUrls = if ($null -ne $origin) { $origin.FetchUrls } else { @() }
        OriginPushUrls = if ($null -ne $origin) { $origin.PushUrls } else { @() }
        BaseBranch = $baseBranch
        Branch = $branch
        Head = $head
        IsClean = $isClean
        Worktree = $worktree
        AheadOfBase = $ahead
        BehindBase = $behind
        Upstream = $upstream
        ExpectedUpstream = $expectedUpstream
        RemoteBranchRefExists = $remoteBranchRefExists
        RemoteTrackingOid = $remoteTrackingOid
        RemoteBranchOid = $remoteBranchOid
        RemoteBranchMatchesTracking = $remoteBranchMatchesTracking
        RemoteBranchError = $remoteBranchError
        UpstreamReady = $upstreamReady
        AheadOfUpstream = $aheadOfUpstream
        BehindUpstream = $behindUpstream
        IssueNumber = $issueNumber
        Issue = $issue
        IssueContractErrors = $issueContractErrors
        LinkedBranchVerified = $linkedBranchVerified
        LinkedBranchError = $linkedBranchError
        PullRequestIssueLinkVerified = $pullRequestIssueLinkVerified
        PullRequestClosingReferenceDetected = $pullRequestClosingReferenceDetected
        IssueChangeLinkVerified = $issueChangeLinkVerified
        PullRequestQueryVerified = $pullRequestQueryVerified
        GovernedContextValid = $governedContextValid
        PullRequests = $pullRequests
        GitHubAuthorized = $githubAuthorized
        GitHubError = $githubError
        NextAction = $nextAction
    }
}
finally {
    Pop-Location
}
