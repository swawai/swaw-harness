param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = 'Stop'

function Write-Call {
    param([string]$Name)

    [IO.File]::AppendAllText(
        $env:GOVERN_FAKE_LOG,
        $Name + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Stop-FakeCommand {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 1
}

$scenario = $env:GOVERN_FAKE_SCENARIO
Write-Call "scenario=$scenario"
if ($CommandArgs[0] -in @('issue', 'pr') -and
    $CommandArgs -notcontains 'swawai/offline-fixture') {
    Stop-FakeCommand 'wrong --repo target'
}
if ($CommandArgs[0] -ceq '.doctor') {
    Write-Call 'doctor'
    if ($scenario -ceq 'auth-failure') {
        Stop-FakeCommand 'offline authentication denied'
    }
    exit 0
}
if ($CommandArgs[0] -ceq 'repo' -and $CommandArgs[1] -ceq 'view') {
    Write-Call 'repo-view'
    [Console]::Out.WriteLine('cli/unrelated-upstream')
    exit 0
}
if ($CommandArgs[0] -ceq 'api') {
    $methodIndex = [Array]::IndexOf($CommandArgs, '--method')
    if ($methodIndex -lt 0) { Stop-FakeCommand 'missing API method' }
    $method = $CommandArgs[$methodIndex + 1]
    $endpoint = @($CommandArgs | Where-Object {
        $_.StartsWith('repos/', [StringComparison]::Ordinal)
    }) | Select-Object -First 1
    if ($method -ceq 'GET' -and
        $endpoint -ceq (
            'repos/swawai/offline-fixture/git/ref/heads/' +
            'codex/42-test-change'
        )) {
        Write-Call 'remote-ref-read'
        if ($scenario -ceq 'remote-ref-failure') {
            Stop-FakeCommand 'offline remote ref lookup failed'
        }
        $remoteOid = if ($scenario -ceq 'remote-ahead-unfetched') {
            '1111111111111111111111111111111111111111'
        }
        else {
            $remoteRef = 'refs/remotes/origin/codex/42-test-change'
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $remoteOid = (& git rev-parse $remoteRef 2>$null).Trim()
            if ($LASTEXITCODE -ne 0) {
                $remoteOid = (& git rev-parse HEAD).Trim()
            }
            $ErrorActionPreference = $oldPreference
            $remoteOid
        }
        [pscustomobject]@{
            ref = 'refs/heads/codex/42-test-change'
            object = [pscustomobject]@{ type = 'commit'; sha = $remoteOid }
        } | ConvertTo-Json -Compress | Write-Output
        exit 0
    }
    Write-Call 'api-create'
    if ($method -cne 'POST') { Stop-FakeCommand 'Issue API must use POST' }
    if ($endpoint -cne 'repos/swawai/offline-fixture/issues') {
        Stop-FakeCommand 'wrong API target'
    }
    $inputIndex = [Array]::IndexOf($CommandArgs, '--input')
    if ($inputIndex -lt 0) { Stop-FakeCommand 'missing --input' }
    [IO.File]::Copy(
        $CommandArgs[$inputIndex + 1],
        $env:GOVERN_FAKE_PAYLOAD,
        $true
    )
    if ($scenario -ceq 'issue-uncertain') {
        Stop-FakeCommand 'offline transport timeout'
    }
    [Console]::Out.WriteLine(
        '{"number":42,"html_url":"https://example.invalid/issues/42"}'
    )
    exit 0
}
if ($CommandArgs[0] -ceq 'issue' -and $CommandArgs[1] -ceq 'view') {
    Write-Call 'issue-view'
    if ($scenario -ceq 'missing') { Stop-FakeCommand 'offline Issue not found' }
    $payload = Get-Content -LiteralPath $env:GOVERN_FAKE_PAYLOAD -Raw |
        ConvertFrom-Json
    $body = [string]$payload.body
    if ($scenario -ceq 'malformed') {
        $body = '### Outcome'
    }
    elseif ($scenario -ceq 'heading-suffix') {
        $body = $body.Replace('### Outcome', '### OutcomeUnexpected')
    }
    elseif ($scenario -ceq 'commented-contract') {
        $body = "<!--`n$body`n-->"
    }
    elseif ($scenario -ceq 'fenced-contract') {
        $body = '```text' + "`n" + $body + "`n" + '```'
    }
    elseif ($scenario -ceq 'higher-heading-boundary') {
        $body = [regex]::Replace(
            $body,
            '(?ms)^### Outcome[ `t]*\r?\n.*?(?=^### Reason)',
            "### Outcome`n`n## Outside`nNot outcome content.`n`n"
        )
    }
    elseif ($scenario -ceq 'lowercase-heading') {
        $body = $body.Replace('### Outcome', '### outcome')
    }
    elseif ($scenario -ceq 'indented-readiness') {
        $body = [regex]::Replace(
            $body,
            '(?m)^(- \[[xX]\] (?:The outcome|Unknowns|Version-controlled).*)$',
            '    $1'
        )
    }
    $state = if ($scenario -ceq 'closed') { 'CLOSED' } else { 'OPEN' }
    [pscustomobject]@{
        number = 42
        title = 'Offline fixture'
        state = $state
        url = 'https://example.invalid/issues/42'
        body = $body
    } | ConvertTo-Json -Compress | Write-Output
    exit 0
}
if ($CommandArgs[0] -ceq 'issue' -and $CommandArgs[1] -ceq 'develop') {
    if ($CommandArgs -contains '--list') {
        Write-Call 'issue-develop-list'
        if ($scenario -notin @('unlinked', 'open-pr', 'open-pr-unlinked')) {
            $branch = (& git branch --show-current).Trim()
            $linkedRepo = if ($scenario -ceq 'wrong-linked-repo') {
                'cli/cli'
            }
            else {
                'swawai/offline-fixture'
            }
            [Console]::Out.WriteLine(
                "$branch https://github.com/$linkedRepo/tree/$branch"
            )
        }
        exit 0
    }
    Write-Call 'issue-develop-create'
    if ($scenario -ceq 'branch-failure') {
        Stop-FakeCommand 'offline branch creation failed'
    }
    $nameIndex = [Array]::IndexOf($CommandArgs, '--name')
    if ($nameIndex -lt 0) { Stop-FakeCommand 'missing --name' }
    $baseIndex = [Array]::IndexOf($CommandArgs, '--base')
    if ($baseIndex -lt 0 -or $CommandArgs[$baseIndex + 1] -cne 'main') {
        Stop-FakeCommand 'linked branch creation must use base main'
    }
    if ($CommandArgs -notcontains '--checkout') {
        Stop-FakeCommand 'linked branch creation must check out the branch'
    }
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git switch --quiet -c $CommandArgs[$nameIndex + 1] 1>$null 2>$null
    $gitExitCode = $LASTEXITCODE
    if ($gitExitCode -eq 0) {
        $branchName = $CommandArgs[$nameIndex + 1]
        & git update-ref "refs/remotes/origin/$branchName" HEAD 1>$null 2>$null
        $gitExitCode = $LASTEXITCODE
        if ($gitExitCode -eq 0) {
            & git branch --quiet --set-upstream-to="origin/$branchName" $branchName `
                1>$null 2>$null
            $gitExitCode = $LASTEXITCODE
        }
    }
    $ErrorActionPreference = $oldPreference
    if ($gitExitCode -ne 0) {
        Stop-FakeCommand 'fixture branch checkout failed'
    }
    exit 0
}
if ($CommandArgs[0] -ceq 'pr' -and $CommandArgs[1] -ceq 'list') {
    Write-Call 'pr-list'
    $baseIndex = [Array]::IndexOf($CommandArgs, '--base')
    if ($baseIndex -lt 0 -or $CommandArgs[$baseIndex + 1] -cne 'main') {
        Stop-FakeCommand 'PR lookup must target main'
    }
    $headIndex = [Array]::IndexOf($CommandArgs, '--head')
    $currentBranch = (& git branch --show-current).Trim()
    if ($headIndex -lt 0 -or
        $CommandArgs[$headIndex + 1] -cne $currentBranch) {
        Stop-FakeCommand 'PR lookup must target the current branch'
    }
    $jsonIndex = [Array]::IndexOf($CommandArgs, '--json')
    if ($jsonIndex -lt 0 -or
        $CommandArgs[$jsonIndex + 1] -notmatch 'headRepository' -or
        $CommandArgs[$jsonIndex + 1] -notmatch 'baseRefName' -or
        $CommandArgs[$jsonIndex + 1] -notmatch 'body') {
        Stop-FakeCommand 'PR lookup must request repository identity fields'
    }
    if ($scenario -ceq 'pr-failure') {
        Stop-FakeCommand 'offline PR lookup failed'
    }
    if ($scenario -in @(
        'open-pr',
        'open-pr-unlinked',
        'wrong-pr-repo',
        'wrong-pr-base',
        'wrong-pr-head'
    )) {
        $headRepository = if ($scenario -ceq 'wrong-pr-repo') {
            'someone/offline-fixture'
        }
        else {
            'swawai/offline-fixture'
        }
        $baseRef = if ($scenario -ceq 'wrong-pr-base') { 'develop' } else { 'main' }
        $headRef = if ($scenario -ceq 'wrong-pr-head') {
            'codex/99-other-change'
        }
        else {
            'codex/42-test-change'
        }
        [pscustomobject]@{
            number = 7
            title = 'Offline PR'
            state = 'OPEN'
            isDraft = $false
            url = 'https://example.invalid/pull/7'
            mergeStateStatus = 'CLEAN'
            statusCheckRollup = @()
            body = if ($scenario -ceq 'open-pr-unlinked') {
                'Refs: #42'
            }
            else {
                'Closes #42'
            }
            headRefName = $headRef
            headRepository = [pscustomobject]@{
                name = 'offline-fixture'
                nameWithOwner = $headRepository
            }
            headRepositoryOwner = [pscustomobject]@{
                login = ($headRepository -split '/', 2)[0]
            }
            baseRefName = $baseRef
        } | ConvertTo-Json -Depth 5 -Compress | Write-Output
    }
    else {
        [Console]::Out.WriteLine('[]')
    }
    exit 0
}
Stop-FakeCommand ('unexpected fake ghswaw command: ' + ($CommandArgs -join ' '))
