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

function Get-ManagedRulesetName {
    if ([string]::IsNullOrWhiteSpace($env:RULESET_FAKE_NAME)) {
        return 'protect-main'
    }
    return $env:RULESET_FAKE_NAME
}

function Write-RemoteDetail {
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][long]$Id
    )

    $config = Get-Content -LiteralPath $StatePath -Raw |
        ConvertFrom-Json
    $pullRequest = @($config.rules | Where-Object {
        $_.type -ceq 'pull_request'
    })[0]
    if ($null -ne $pullRequest) {
        $pullRequest.parameters | Add-Member `
            -NotePropertyName require_extra_approval_for_unattributed_changes `
            -NotePropertyValue $true `
            -Force
    }
    $sourceType = if ($env:RULESET_FAKE_SCENARIO -ceq 'wrong-detail-owner') {
        'Organization'
    }
    else {
        'Repository'
    }
    $detailId = if ($env:RULESET_FAKE_SCENARIO -ceq 'wrong-detail-id') {
        $Id + 1
    }
    else { $Id }
    $detailName = if ($env:RULESET_FAKE_SCENARIO -ceq 'wrong-detail-name') {
        'renamed-between-reads'
    }
    else { $config.name }
    [pscustomobject][ordered]@{
        id = $detailId
        name = $detailName
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

function Get-RulesetResource {
    param([Parameter(Mandatory = $true)][string]$Endpoint)

    $match = [regex]::Match($Endpoint, '/rulesets/(?<id>[0-9]+)$')
    if (-not $match.Success) {
        Stop-FakeCommand "Ruleset resource endpoint is invalid: $Endpoint"
    }
    $id = [long]$match.Groups['id'].Value
    if ($id -eq 77) {
        return [pscustomobject]@{ Id = $id; StatePath = $env:RULESET_FAKE_STATE }
    }
    if ($id -eq 88 -and
        -not [string]::IsNullOrWhiteSpace($env:RULESET_FAKE_OTHER_STATE)) {
        return [pscustomobject]@{
            Id = $id
            StatePath = $env:RULESET_FAKE_OTHER_STATE
        }
    }
    if ($id -eq 99 -and
        -not [string]::IsNullOrWhiteSpace($env:RULESET_FAKE_PRODUCT_STATE)) {
        return [pscustomobject]@{
            Id = $id
            StatePath = $env:RULESET_FAKE_PRODUCT_STATE
        }
    }
    Stop-FakeCommand "Ruleset resource id is not managed by the fixture: $id"
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
if ($method -ceq 'GET' -and
    $endpoint -ceq 'repos/swawai/offline-fixture/git/ref/heads/main') {
    Write-Call "api:${method}:$endpoint"
    if ([string]::IsNullOrWhiteSpace($env:RULESET_FAKE_MAIN_OID)) {
        Stop-FakeCommand 'missing fake main OID'
    }
    [pscustomobject]@{
        object = [pscustomobject]@{ sha = $env:RULESET_FAKE_MAIN_OID }
    } | ConvertTo-Json -Compress | Write-Output
    exit 0
}
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
    if ($scenario -ceq 'drift-before-mutation' -and $page -eq 1 -and
        [IO.File]::Exists($env:RULESET_FAKE_STATE)) {
        $listCount = @([IO.File]::ReadAllLines($env:RULESET_FAKE_LOG) |
            Where-Object { $_ -ceq 'list-page:1' }).Count
        if ($listCount -ge 2) {
            $changed = Get-Content -LiteralPath $env:RULESET_FAKE_STATE -Raw |
                ConvertFrom-Json
            $changed.target = 'tag'
            [IO.File]::WriteAllText(
                $env:RULESET_FAKE_STATE,
                ($changed | ConvertTo-Json -Depth 100),
                [Text.UTF8Encoding]::new($false)
            )
        }
    }
    if ($scenario -cin @(
        'product-drift-before-delete',
        'product-drift-after-delete'
    ) -and $page -eq 1 -and
        [IO.File]::Exists($env:RULESET_FAKE_PRODUCT_STATE)) {
        $listCount = @([IO.File]::ReadAllLines($env:RULESET_FAKE_LOG) |
            Where-Object { $_ -ceq 'list-page:1' }).Count
        $threshold = if ($scenario -ceq 'product-drift-before-delete') {
            4
        }
        else { 6 }
        if ($listCount -ge $threshold) {
            $changedProduct = Get-Content `
                -LiteralPath $env:RULESET_FAKE_PRODUCT_STATE `
                -Raw | ConvertFrom-Json
            $changedProduct.enforcement = 'disabled'
            [IO.File]::WriteAllText(
                $env:RULESET_FAKE_PRODUCT_STATE,
                ($changedProduct | ConvertTo-Json -Depth 100),
                [Text.UTF8Encoding]::new($false)
            )
        }
    }
    $summaries = @()
    $managedName = Get-ManagedRulesetName
    if ($scenario -ceq 'duplicate') {
        $summaries = @(
            New-RemoteSummary 77 $managedName
            New-RemoteSummary 78 $managedName
        )
    }
    elseif ($scenario -ceq 'inherited') {
        $summaries = @(
            New-RemoteSummary 77 $managedName 'Organization' 'swawai'
        )
    }
    elseif ($scenario -ceq 'wrong-summary-source') {
        $summaries = @(
            New-RemoteSummary 77 $managedName 'Repository' 'other/repository'
        )
    }
    elseif ($scenario -ceq 'second-page') {
        if ($page -eq 1) {
            $summaries = @(1..100 | ForEach-Object {
                New-RemoteSummary $_ "other-$_"
            })
        }
        elseif ($page -eq 2) {
            $summaries = @(New-RemoteSummary 77 $managedName)
        }
    }
    elseif ([IO.File]::Exists($env:RULESET_FAKE_STATE)) {
        $config = Get-Content -LiteralPath $env:RULESET_FAKE_STATE -Raw |
            ConvertFrom-Json
        $summaries = @(New-RemoteSummary 77 $config.name)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:RULESET_FAKE_OTHER_STATE) -and
        [IO.File]::Exists($env:RULESET_FAKE_OTHER_STATE)) {
        $otherConfig = Get-Content `
            -LiteralPath $env:RULESET_FAKE_OTHER_STATE `
            -Raw | ConvertFrom-Json
        $summaries = @($summaries) + @(
            New-RemoteSummary 88 ([string]$otherConfig.name)
        )
    }
    if (-not [string]::IsNullOrWhiteSpace($env:RULESET_FAKE_PRODUCT_STATE) -and
        [IO.File]::Exists($env:RULESET_FAKE_PRODUCT_STATE)) {
        $productConfig = Get-Content `
            -LiteralPath $env:RULESET_FAKE_PRODUCT_STATE `
            -Raw | ConvertFrom-Json
        $summaries = @($summaries) + @(
            New-RemoteSummary 99 ([string]$productConfig.name)
        )
    }
    ConvertTo-Json -InputObject @($summaries) -Depth 10 -Compress |
        Write-Output
    exit 0
}
if ($method -ceq 'GET') {
    $resource = Get-RulesetResource -Endpoint $endpoint
    if (-not [IO.File]::Exists($resource.StatePath)) {
        Stop-FakeCommand 'offline Ruleset not found'
    }
    Write-RemoteDetail -StatePath $resource.StatePath -Id $resource.Id
    exit 0
}
if ($method -ceq 'DELETE') {
    Write-Call 'mutate:DELETE'
    $resource = Get-RulesetResource -Endpoint $endpoint
    if (-not [IO.File]::Exists($resource.StatePath)) {
        Stop-FakeCommand 'offline Ruleset does not exist'
    }
    [IO.File]::Delete($resource.StatePath)
    if ($scenario -ceq 'delete-applied-unknown') {
        Stop-FakeCommand 'offline response lost after delete'
    }
    exit 0
}
if ($method -notin @('POST', 'PUT')) {
    Stop-FakeCommand "unexpected method: $method"
}
Write-Call "mutate:$method"
$targetResource = if ($method -ceq 'POST') {
    if ($endpoint -cne 'repos/swawai/offline-fixture/rulesets') {
        Stop-FakeCommand "Ruleset collection endpoint is invalid: $endpoint"
    }
    if (-not [IO.File]::Exists($env:RULESET_FAKE_STATE)) {
        [pscustomobject]@{ Id = 77; StatePath = $env:RULESET_FAKE_STATE }
    }
    elseif (-not [string]::IsNullOrWhiteSpace(
        $env:RULESET_FAKE_OTHER_STATE
    ) -and -not [IO.File]::Exists($env:RULESET_FAKE_OTHER_STATE)) {
        [pscustomobject]@{ Id = 88; StatePath = $env:RULESET_FAKE_OTHER_STATE }
    }
    else {
        Stop-FakeCommand 'offline fixture has no free Ruleset creation slot'
    }
}
else {
    Get-RulesetResource -Endpoint $endpoint
}
$inputIndex = [Array]::IndexOf($CommandArgs, '--input')
if ($inputIndex -lt 0) { Stop-FakeCommand 'missing --input' }
if ($scenario -ceq 'mutation-unknown') {
    Stop-FakeCommand 'offline transport timeout'
}
[IO.File]::Copy(
    $CommandArgs[$inputIndex + 1],
    $targetResource.StatePath,
    $true
)
if ($scenario -ceq 'mutation-applied-unknown') {
    Stop-FakeCommand 'offline response lost after mutation'
}
Write-Output ('{"id":' + $targetResource.Id + '}')
