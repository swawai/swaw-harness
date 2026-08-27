[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [string]$Prefix
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..'
}

$Root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$TrackedFiles = @(
    & git -C $Root ls-files --cached --others --exclude-standard -- `
        '*.md' ':(glob)**/*.md'
)
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot enumerate the repository rule files with git.'
}

$Files = @(
    $TrackedFiles |
        Where-Object {
            Test-Path `
                -LiteralPath (Join-Path $Root $_) `
                -PathType Leaf
        } |
        Sort-Object -Unique
)
if ($Files.Count -eq 0) {
    throw 'No repository rule files were found.'
}

$Rules = [System.Collections.Generic.List[object]]::new()
$Owners = [System.Collections.Generic.List[object]]::new()

foreach ($RelativePath in $Files) {
    $Path = Join-Path $Root $RelativePath
    $NormalizedPath = $RelativePath.Replace('\', '/')
    $IsAgentFile = $NormalizedPath -cmatch '(^|/)AGENTS\.md$'
    $Lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $Section = ''
    $Heading = ''
    $DeclaredPrefix = $null
    $FenceCharacter = ''
    $FenceLength = 0

    foreach ($Line in $Lines) {
        if ($FenceLength -gt 0) {
            $ClosingFencePattern =
                '^[ ]{0,3}' +
                [regex]::Escape($FenceCharacter) +
                '{' + $FenceLength + ',}[ \t]*$'
            if ($Line -cmatch $ClosingFencePattern) {
                $FenceCharacter = ''
                $FenceLength = 0
            }
            continue
        }
        if ($Line -cmatch
            '^[ ]{0,3}(?<Marker>`{3,}|~{3,})(?<Info>.*)$') {
            $FenceCharacter = $Matches.Marker.Substring(0, 1)
            $FenceLength = $Matches.Marker.Length
            continue
        }

        if ($Line -cmatch '^## (.+)$') {
            $Heading = $Matches[1]
            if ($IsAgentFile -and $Heading -ceq 'Proposed') {
                throw "Use Open for unresolved rules: $RelativePath"
            }
            if ($Heading -cin @('Accepted', 'Open')) {
                $Section = $Heading
            }
            else {
                $Section = ''
            }
            continue
        }

        if ($IsAgentFile -and
            $Line -cmatch
            'Rule ID \u524D\u7F00\u4E3A `([A-Za-z][A-Za-z0-9-]*)`') {
            $CandidatePrefix = $Matches[1]
            if ($CandidatePrefix -cnotmatch '^[A-Z][A-Z0-9-]*$') {
                throw "Rule ID prefixes must use uppercase ASCII: $RelativePath"
            }
            if ($Heading -cne 'Scope') {
                throw "The Rule ID prefix must be declared in Scope: $RelativePath"
            }
            if ($null -ne $DeclaredPrefix -and
                $DeclaredPrefix -cne $CandidatePrefix) {
                throw "Multiple Rule ID prefixes are declared in $RelativePath."
            }
            $DeclaredPrefix = $CandidatePrefix
        }

        if ($Line -cmatch
            '^- \*\*([A-Za-z][A-Za-z0-9-]*-[0-9]{3}) \p{Pd} ') {
            $RuleId = $Matches[1]
            $IsActiveSection = $Section -cin @('Accepted', 'Open')
            if (-not $IsAgentFile -and -not $IsActiveSection) {
                continue
            }
            if ($RuleId -cnotmatch '^[A-Z][A-Z0-9-]*-[0-9]{3}$') {
                throw "Rule IDs must use uppercase ASCII: $RelativePath"
            }
            if (-not $IsActiveSection) {
                throw "Rule declarations are only valid under Accepted or Open: $RelativePath"
            }
            $Rules.Add([pscustomobject]@{
                    Id = $RuleId
                    Section = $Section
                    File = $NormalizedPath
                })
        }
    }

    if ($null -ne $DeclaredPrefix) {
        $Owners.Add([pscustomobject]@{
                Prefix = $DeclaredPrefix
                File = $NormalizedPath
            })
    }
}

$DuplicateIds = @($Rules | Group-Object Id | Where-Object Count -gt 1)
if ($DuplicateIds.Count -gt 0) {
    throw "Duplicate Rule IDs: $($DuplicateIds.Name -join ', ')"
}

$CurrentPrefixGroups = @(
    $Rules | Group-Object { $_.Id -replace '-[0-9]{3}$', '' }
)
foreach ($PrefixGroup in $CurrentPrefixGroups) {
    $PrefixFiles = @(
        $PrefixGroup.Group | Select-Object -ExpandProperty File -Unique
    )
    if ($PrefixFiles.Count -ne 1) {
        throw "Prefix $($PrefixGroup.Name) is split across owners: $($PrefixFiles -join ', ')"
    }
}

$DuplicatePrefixes = @($Owners | Group-Object Prefix | Where-Object Count -gt 1)
if ($DuplicatePrefixes.Count -gt 0) {
    throw "Rule ID prefixes have multiple owners: $($DuplicatePrefixes.Name -join ', ')"
}

$OwnerFiles = @($Owners | Select-Object -ExpandProperty File)
$NonAgentRuleFiles = @(
    $Rules |
        Where-Object { $_.File -cnotmatch '(^|/)AGENTS\.md$' } |
        Select-Object -ExpandProperty File -Unique
)
if ($NonAgentRuleFiles.Count -gt 0) {
    throw "Active rules may only be declared in AGENTS.md: $($NonAgentRuleFiles -join ', ')"
}

$UnownedLocalFiles = @(
    $Rules |
        Where-Object {
            $_.File -notin $OwnerFiles
        } |
        Select-Object -ExpandProperty File -Unique
)
if ($UnownedLocalFiles.Count -gt 0) {
    throw "Local rule files do not declare a Rule ID prefix: $($UnownedLocalFiles -join ', ')"
}

$Results = [System.Collections.Generic.List[object]]::new()
foreach ($Owner in $Owners) {
    $OwnedPattern = '^' + [regex]::Escape($Owner.Prefix) + '-([0-9]{3})$'
    $OwnedRules = @(
        $Rules | Where-Object {
            $_.File -ceq $Owner.File -and $_.Id -cmatch $OwnedPattern
        }
    )
    $ActiveRules = @(
        $Rules | Where-Object {
            $_.File -ceq $Owner.File -and
            $_.Section -in @('Accepted', 'Open')
        }
    )
    $ForeignActive = @($ActiveRules | Where-Object { $_.Id -cnotmatch $OwnedPattern })
    if ($ForeignActive.Count -gt 0) {
        throw "$($Owner.File) has active IDs outside prefix $($Owner.Prefix): $($ForeignActive.Id -join ', ')"
    }

    $ForeignOwned = @(
        $Rules | Where-Object {
            $_.File -cne $Owner.File -and $_.Id -cmatch $OwnedPattern
        }
    )
    if ($ForeignOwned.Count -gt 0) {
        throw "Prefix $($Owner.Prefix) is used outside $($Owner.File): $($ForeignOwned.File -join ', ')"
    }

    if ($ActiveRules.Count -eq 0) {
        throw "$($Owner.File) declares prefix $($Owner.Prefix) without an active rule."
    }
    if (@($ActiveRules | Where-Object Id -ceq "$($Owner.Prefix)-001").Count -ne 1) {
        throw "$($Owner.File) must have exactly one active $($Owner.Prefix)-001 rule."
    }

    $Maximum = 0
    $OwnedNumbers = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($Rule in $OwnedRules) {
        if ($Rule.Id -cnotmatch $OwnedPattern) {
            throw "Cannot parse the suffix of $($Rule.Id)."
        }
        $Number = [int]$Matches[1]
        [void]$OwnedNumbers.Add($Number)
        if ($Number -gt $Maximum) {
            $Maximum = $Number
        }
    }
    $MissingNumbers = @(
        1..$Maximum | Where-Object { -not $OwnedNumbers.Contains($_) }
    )
    if ($MissingNumbers.Count -gt 0) {
        $MissingIds = @(
            $MissingNumbers | ForEach-Object {
                '{0}-{1:000}' -f $Owner.Prefix, $_
            }
        )
        throw "Prefix $($Owner.Prefix) has missing current IDs: $($MissingIds -join ', ')"
    }
    if ($Maximum -ge 999) {
        throw "Prefix $($Owner.Prefix) has exhausted its three-digit sequence."
    }

    $Results.Add([pscustomobject]@{
            Prefix = $Owner.Prefix
            File = $Owner.File
            Maximum = $Maximum.ToString('000')
            NextId = ('{0}-{1:000}' -f $Owner.Prefix, ($Maximum + 1))
        })
}

$OrderedResults = @($Results | Sort-Object Prefix)
if ([string]::IsNullOrWhiteSpace($Prefix)) {
    $OrderedResults | Format-Table Prefix, Maximum, NextId, File -AutoSize
    Write-Host (
        '[PASS] {0} current Rule IDs are unique; {1} current prefixes each have one file owner; {2} AGENTS.md owners declare a contiguous 001-based local prefix.' -f
        $Rules.Count,
        $CurrentPrefixGroups.Count,
        $Owners.Count
    )
    exit 0
}

$Requested = $Prefix.Trim().ToUpperInvariant()
$Match = @($OrderedResults | Where-Object Prefix -ceq $Requested)
if ($Match.Count -ne 1) {
    throw "Unknown local Rule ID prefix: $Requested"
}
Write-Output $Match[0].NextId
