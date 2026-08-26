$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'repository.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ruleset-state.psm1') -Force

function Invoke-RulesetApi {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    return Invoke-RepositoryCommand `
        -Executable $Ghswaw `
        -Arguments (@(
            'api',
            '-H', 'Accept: application/vnd.github+json',
            '-H', 'X-GitHub-Api-Version: 2026-03-10'
        ) + $Arguments) `
        -Operation $Operation
}

function Get-RemoteRuleset {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$ReservedNamePrefix = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ReservedNamePrefix) -and
        -not $Name.StartsWith(
            $ReservedNamePrefix,
            [StringComparison]::Ordinal
        )) {
        throw "Ruleset name '$Name' is outside reserved prefix '$ReservedNamePrefix'."
    }

    $pageSize = 100
    $page = 1
    $summaries = @()
    do {
        $listOutput = @(Invoke-RulesetApi `
            -Ghswaw $Ghswaw `
            -Arguments @(
                '--method', 'GET',
                "repos/$Repository/rulesets",
                '-f', 'includes_parents=false',
                '-f', "per_page=$pageSize",
                '-f', "page=$page"
            ) `
            -Operation "List GitHub Rulesets page $page")
        try {
            $pageItems = @((($listOutput -join "`n") | ConvertFrom-Json))
        }
        catch {
            throw (
                "GitHub Ruleset list page $page response is invalid JSON: " +
                $_.Exception.Message
            )
        }
        $summaries += $pageItems
        $page++
    } while ($pageItems.Count -eq $pageSize)

    $matches = @($summaries | Where-Object {
        [string]$_.name -ceq $Name
    })
    $reservedSiblings = if ([string]::IsNullOrWhiteSpace(
        $ReservedNamePrefix
    )) {
        @()
    }
    else {
        @($summaries | Where-Object {
            $candidateName = [string]$_.name
            $candidateName.StartsWith(
                $ReservedNamePrefix,
                [StringComparison]::OrdinalIgnoreCase
            ) -and $candidateName -cne $Name
        })
    }
    foreach ($match in @($matches) + @($reservedSiblings)) {
        Assert-RepositoryRulesetOwnership `
            -Ruleset $match `
            -Repository $Repository `
            -Owner "GitHub Ruleset summary '$($match.name)'"
    }
    $reservedNameCollisions = @($reservedSiblings | ForEach-Object {
        $id = [long]$_.id
        if ($id -le 0) {
            throw "GitHub Ruleset '$($_.name)' has an invalid id."
        }
        [pscustomobject][ordered]@{
            Name = [string]$_.name
            Id = $id
        }
    })
    if ($reservedNameCollisions.Count -gt 0) {
        $reservedNameCollisions = @($reservedNameCollisions | Sort-Object Name)
    }
    if ($matches.Count -gt 1) {
        throw "GitHub returned multiple Rulesets named '$Name'."
    }
    if ($matches.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Id = $null
            Actual = $null
            ReservedNameCollisions = $reservedNameCollisions
        }
    }

    $rulesetId = [long]$matches[0].id
    if ($rulesetId -le 0) {
        throw "GitHub Ruleset '$Name' has an invalid id."
    }
    $detailOutput = @(Invoke-RulesetApi `
        -Ghswaw $Ghswaw `
        -Arguments @(
            '--method', 'GET',
            "repos/$Repository/rulesets/$rulesetId"
        ) `
        -Operation 'Read GitHub Ruleset')
    try {
        $detail = ($detailOutput -join "`n") | ConvertFrom-Json
    }
    catch {
        throw "GitHub Ruleset response is invalid JSON: $($_.Exception.Message)"
    }
    foreach ($property in @('id', 'name')) {
        if ($null -eq $detail.PSObject.Properties[$property]) {
            throw "GitHub Ruleset response is missing property '$property'."
        }
    }
    if ([long]$detail.id -ne $rulesetId -or
        [string]$detail.name -cne $Name) {
        throw (
            "GitHub Ruleset identity changed between list and detail reads; " +
            "expected '$Name' (#$rulesetId), received '$($detail.name)' " +
            "(#$($detail.id)). No mutation is safe."
        )
    }
    Assert-RepositoryRulesetOwnership `
        -Ruleset $detail `
        -Repository $Repository `
        -Owner "GitHub Ruleset '$Name'"
    return [pscustomobject][ordered]@{
        Id = $rulesetId
        Actual = Select-RulesetConfiguration -Ruleset $detail
        ReservedNameCollisions = $reservedNameCollisions
    }
}

function Set-GitHubRuleset {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$PayloadPath,
        [long]$RulesetId = 0
    )

    $isCreate = $RulesetId -le 0
    $method = if ($isCreate) { 'POST' } else { 'PUT' }
    $endpoint = if ($isCreate) {
        "repos/$Repository/rulesets"
    }
    else {
        "repos/$Repository/rulesets/$RulesetId"
    }
    [void](Invoke-RulesetApi `
        -Ghswaw $Ghswaw `
        -Arguments @(
            '--method', $method,
            $endpoint,
            '--input', $PayloadPath
        ) `
        -Operation "$method GitHub Ruleset")
}

function New-RulesetPayloadSnapshot {
    param([Parameter(Mandatory = $true)]$Ruleset)

    $path = Join-Path ([IO.Path]::GetTempPath()) (
        'swaw-ruleset-' + [guid]::NewGuid().ToString('N') + '.json'
    )
    [IO.File]::WriteAllText(
        $path,
        ($Ruleset | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
    return $path
}

function Remove-GitHubRuleset {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][long]$RulesetId
    )

    [void](Invoke-RulesetApi `
        -Ghswaw $Ghswaw `
        -Arguments @(
            '--method', 'DELETE',
            "repos/$Repository/rulesets/$RulesetId"
        ) `
        -Operation 'DELETE GitHub Ruleset')
}

Export-ModuleMember -Function @(
    'Get-RemoteRuleset',
    'Invoke-RulesetApi',
    'New-RulesetPayloadSnapshot',
    'Remove-GitHubRuleset',
    'Set-GitHubRuleset'
)
