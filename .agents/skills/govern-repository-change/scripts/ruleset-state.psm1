$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:managedRulesetName = 'protect-main'

function Get-JsonDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    if (-not [IO.File]::Exists($Path)) {
        throw "$Owner does not exist: $Path"
    }
    try {
        return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) |
            ConvertFrom-Json
    }
    catch {
        throw "$Owner is not valid JSON: $($_.Exception.Message)"
    }
}

function Get-DesiredRuleset {
    param([Parameter(Mandatory = $true)][string]$Path)

    $document = Get-JsonDocument -Path $Path -Owner 'Ruleset file'
    $allowed = @(
        'name',
        'target',
        'enforcement',
        'bypass_actors',
        'conditions',
        'rules'
    )
    $properties = @($document.PSObject.Properties.Name)
    foreach ($name in $allowed) {
        if ($properties -cnotcontains $name) {
            throw "Ruleset file is missing top-level property '$name'."
        }
    }
    foreach ($name in $properties) {
        if ($allowed -cnotcontains $name) {
            throw "Ruleset file contains unsupported top-level property '$name'."
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$document.name)) {
        throw "Ruleset property 'name' must not be empty."
    }
    if ([string]$document.name -cne $script:managedRulesetName) {
        throw (
            "Ruleset name is a stable remote identity and must remain " +
            "'$script:managedRulesetName'. Rename it only through an explicit " +
            'migration that also removes the old remote Ruleset.'
        )
    }
    if ([string]$document.target -cnotin @('branch', 'tag', 'push')) {
        throw "Ruleset property 'target' is invalid."
    }
    if ([string]$document.enforcement -cnotin @(
        'active', 'disabled', 'evaluate'
    )) {
        throw "Ruleset property 'enforcement' is invalid."
    }
    if ($null -eq $document.conditions) {
        throw "Ruleset property 'conditions' must not be null."
    }
    if (@($document.rules).Count -eq 0) {
        throw "Ruleset property 'rules' must contain at least one rule."
    }
    return $document
}

function Select-RulesetConfiguration {
    param([Parameter(Mandatory = $true)]$Ruleset)

    $required = @(
        'name',
        'target',
        'enforcement',
        'bypass_actors',
        'conditions',
        'rules'
    )
    foreach ($name in $required) {
        if ($null -eq $Ruleset.PSObject.Properties[$name]) {
            throw "GitHub Ruleset response is missing property '$name'."
        }
    }
    return [pscustomobject][ordered]@{
        name = $Ruleset.name
        target = $Ruleset.target
        enforcement = $Ruleset.enforcement
        bypass_actors = @($Ruleset.bypass_actors)
        conditions = $Ruleset.conditions
        rules = @($Ruleset.rules)
    }
}

function Assert-RepositoryRulesetOwnership {
    param(
        [Parameter(Mandatory = $true)]$Ruleset,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    foreach ($property in @('source_type', 'source')) {
        if ($null -eq $Ruleset.PSObject.Properties[$property]) {
            throw "$Owner is missing property '$property'."
        }
    }
    $isRepository = [string]$Ruleset.source_type -ceq 'Repository'
    $isExpectedSource = [string]::Equals(
        [string]$Ruleset.source,
        $Repository,
        [StringComparison]::OrdinalIgnoreCase
    )
    if (-not $isRepository -or -not $isExpectedSource) {
        throw (
            "$Owner is not owned by repository '$Repository' " +
            "(source_type='$($Ruleset.source_type)', source='$($Ruleset.source)')."
        )
    }
}

function Test-RulesetDesiredState {
    param($Desired, $Actual)

    if ($null -eq $Desired) {
        return $null -eq $Actual
    }
    $desiredIsObject = $Desired -is [Collections.IDictionary] -or
        $Desired -is [PSCustomObject]
    if ($desiredIsObject) {
        $actualIsObject = $Actual -is [Collections.IDictionary] -or
            $Actual -is [PSCustomObject]
        if (-not $actualIsObject) {
            return $false
        }
        $members = if ($Desired -is [Collections.IDictionary]) {
            @($Desired.Keys | ForEach-Object { [string]$_ })
        }
        else {
            @($Desired.PSObject.Properties.Name)
        }
        foreach ($name in $members) {
            if ($Desired -is [Collections.IDictionary]) {
                $desiredChild = $Desired[$name]
            }
            else {
                $desiredChild = $Desired.PSObject.Properties[$name].Value
            }
            if ($Actual -is [Collections.IDictionary]) {
                if (-not $Actual.Contains($name)) {
                    return $false
                }
                $actualChild = $Actual[$name]
            }
            else {
                $actualProperty = $Actual.PSObject.Properties[$name]
                if ($null -eq $actualProperty) {
                    return $false
                }
                $actualChild = $actualProperty.Value
            }
            if (-not (Test-RulesetDesiredState `
                -Desired $desiredChild `
                -Actual $actualChild
            )) {
                return $false
            }
        }
        return $true
    }

    $desiredIsArray = $Desired -is [Collections.IEnumerable] -and
        $Desired -isnot [string]
    if ($desiredIsArray) {
        $actualIsArray = $Actual -is [Collections.IEnumerable] -and
            $Actual -isnot [string] -and
            $Actual -isnot [Collections.IDictionary]
        if (-not $actualIsArray) {
            return $false
        }
        $desiredItems = @($Desired)
        $actualItems = @($Actual)
        if ($desiredItems.Count -ne $actualItems.Count) {
            return $false
        }
        $matched = [bool[]]::new($actualItems.Count)
        foreach ($desiredItem in $desiredItems) {
            $found = $false
            for ($index = 0; $index -lt $actualItems.Count; $index++) {
                if (-not $matched[$index] -and
                    (Test-RulesetDesiredState `
                        -Desired $desiredItem `
                        -Actual $actualItems[$index]
                    )) {
                    $matched[$index] = $true
                    $found = $true
                    break
                }
            }
            if (-not $found) {
                return $false
            }
        }
        return $true
    }

    return (ConvertTo-Json -InputObject $Desired -Compress) -ceq
        (ConvertTo-Json -InputObject $Actual -Compress)
}

Export-ModuleMember -Function @(
    'Assert-RepositoryRulesetOwnership',
    'Get-DesiredRuleset',
    'Select-RulesetConfiguration',
    'Test-RulesetDesiredState'
)
