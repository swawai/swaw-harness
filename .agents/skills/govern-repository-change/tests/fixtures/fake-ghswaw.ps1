param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

$ErrorActionPreference = 'Stop'

function Write-Call {
    param([string]$Name)

    [IO.File]::AppendAllText(
        $env:RULESET_FAKE_LOG,
        $Name + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

function Stop-FakeCommand {
    param([string]$Message)

    [Console]::Error.WriteLine($Message)
    exit 1
}

function New-RemoteSummary {
    param(
        [long]$Id,
        [string]$Name,
        [string]$SourceType = 'Repository',
        [string]$Source = 'swawai/offline-fixture'
    )

    return [pscustomobject][ordered]@{
        id = $Id
        name = $Name
        source_type = $SourceType
        source = $Source
    }
}

function Write-RemoteDetail {
    $config = Get-Content -LiteralPath $env:RULESET_FAKE_STATE -Raw |
        ConvertFrom-Json
    $pullRequest = @($config.rules | Where-Object {
        $_.type -ceq 'pull_request'
    })[0]
    $pullRequest.parameters | Add-Member `
        -NotePropertyName require_extra_approval_for_unattributed_changes `
        -NotePropertyValue $true `
        -Force
    $sourceType = if ($env:RULESET_FAKE_SCENARIO -ceq 'wrong-detail-owner') {
        'Organization'
    }
    else {
        'Repository'
    }
    [pscustomobject][ordered]@{
        id = 77
        name = $config.name
        target = $config.target
        source_type = $sourceType
        source = 'swawai/offline-fixture'
        enforcement = $config.enforcement
        bypass_actors = @($config.bypass_actors)
        conditions = $config.conditions
        rules = @($config.rules)
        created_at = '2026-01-01T00:00:00Z'
    } | ConvertTo-Json -Depth 100 -Compress | Write-Output
}

$scenario = $env:RULESET_FAKE_SCENARIO
if ($CommandArgs[0] -ceq '.doctor') {
    Write-Call 'doctor'
    exit 0
}
if ($CommandArgs[0] -cne 'api') {
    Stop-FakeCommand ('unexpected fake ghswaw command: ' + ($CommandArgs -join ' '))
}
$methodIndex = [Array]::IndexOf($CommandArgs, '--method')
if ($methodIndex -lt 0) { Stop-FakeCommand 'missing --method' }
$method = $CommandArgs[$methodIndex + 1]
$endpoint = @($CommandArgs | Where-Object {
    $_.StartsWith('repos/', [StringComparison]::Ordinal)
}) | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($endpoint) -or
    -not $endpoint.StartsWith(
        'repos/swawai/offline-fixture/rulesets',
        [StringComparison]::Ordinal
    )) {
    Stop-FakeCommand "wrong API target: $endpoint"
}
Write-Call "api:${method}:$endpoint"
if ($scenario -ceq 'read-failure' -and $method -ceq 'GET') {
    Stop-FakeCommand 'offline Ruleset read failed'
}
if ($scenario -ceq 'verification-failure' -and
    $method -ceq 'GET' -and
    [IO.File]::Exists($env:RULESET_FAKE_STATE)) {
    Stop-FakeCommand 'offline post-write verification failed'
}

if ($method -ceq 'GET' -and
    $endpoint -ceq 'repos/swawai/offline-fixture/rulesets') {
    $fields = @{}
    for ($index = 0; $index -lt $CommandArgs.Count; $index++) {
        if ($CommandArgs[$index] -ceq '-f' -and
            $index + 1 -lt $CommandArgs.Count) {
            $parts = $CommandArgs[$index + 1] -split '=', 2
            if ($parts.Count -eq 2) { $fields[$parts[0]] = $parts[1] }
        }
    }
    if ([string]$fields.includes_parents -cne 'false') {
        Stop-FakeCommand 'Ruleset list must exclude parent Rulesets'
    }
    $page = 0
    if (-not [int]::TryParse([string]$fields.page, [ref]$page) -or $page -le 0) {
        Stop-FakeCommand 'Ruleset list must declare a positive page'
    }
    if ([string]$fields.per_page -cne '100') {
        Stop-FakeCommand 'Ruleset list must request 100 items per page'
    }
    Write-Call "list-page:$page"
    $summaries = @()
    if ($scenario -ceq 'duplicate') {
        $summaries = @(
            New-RemoteSummary 77 'protect-main'
            New-RemoteSummary 78 'protect-main'
        )
    }
    elseif ($scenario -ceq 'inherited') {
        $summaries = @(
            New-RemoteSummary 77 'protect-main' 'Organization' 'swawai'
        )
    }
    elseif ($scenario -ceq 'wrong-summary-source') {
        $summaries = @(
            New-RemoteSummary 77 'protect-main' 'Repository' 'other/repository'
        )
    }
    elseif ($scenario -ceq 'second-page') {
        if ($page -eq 1) {
            $summaries = @(1..100 | ForEach-Object {
                New-RemoteSummary $_ "other-$_"
            })
        }
        elseif ($page -eq 2) {
            $summaries = @(New-RemoteSummary 77 'protect-main')
        }
    }
    elseif ([IO.File]::Exists($env:RULESET_FAKE_STATE)) {
        $config = Get-Content -LiteralPath $env:RULESET_FAKE_STATE -Raw |
            ConvertFrom-Json
        $summaries = @(New-RemoteSummary 77 $config.name)
    }
    ConvertTo-Json -InputObject @($summaries) -Depth 10 -Compress |
        Write-Output
    exit 0
}
if ($method -ceq 'GET') {
    if (-not [IO.File]::Exists($env:RULESET_FAKE_STATE)) {
        Stop-FakeCommand 'offline Ruleset not found'
    }
    Write-RemoteDetail
    exit 0
}
if ($method -notin @('POST', 'PUT')) {
    Stop-FakeCommand "unexpected method: $method"
}
Write-Call "mutate:$method"
$inputIndex = [Array]::IndexOf($CommandArgs, '--input')
if ($inputIndex -lt 0) { Stop-FakeCommand 'missing --input' }
if ($scenario -ceq 'mutation-unknown') {
    Stop-FakeCommand 'offline transport timeout'
}
[IO.File]::Copy(
    $CommandArgs[$inputIndex + 1],
    $env:RULESET_FAKE_STATE,
    $true
)
Write-Output '{"id":77}'
