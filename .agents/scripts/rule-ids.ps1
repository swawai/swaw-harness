[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..\..'),
    [string]$Prefix
)

$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$TrackedFiles = @(
    & git -C $Root ls-files --cached --others --exclude-standard -- `
        'AGENTS.md' ':(glob)**/AGENTS.md' 'docs/swaw-harness-spec.md'
)
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot enumerate the repository rule files with git.'
}

$Files = @($TrackedFiles | Sort-Object -Unique)
if ($Files.Count -eq 0) {
    throw 'No repository rule files were found.'
}

$Rules = [System.Collections.Generic.List[object]]::new()
$Owners = [System.Collections.Generic.List[object]]::new()

foreach ($RelativePath in $Files) {
    $Path = Join-Path $Root $RelativePath
    $Lines = @(Get-Content -LiteralPath $Path)
    $Section = ''
    $Heading = ''
    $DeclaredPrefix = $null

    foreach ($Line in $Lines) {
        if ($Line -match '^## (.+)$') {
            $Heading = $Matches[1]
            if ($Heading -ceq 'Proposed') {
                throw "Use Open for unresolved rules: $RelativePath"
            }
            if ($Heading -in @('Accepted', 'Open', 'Superseded')) {
                $Section = $Heading
            }
            else {
                $Section = ''
            }
            continue
        }

        if ($Line -match 'Rule ID 前缀为 `([A-Z][A-Z0-9-]*)`') {
            if ($Heading -cne 'Scope') {
                throw "The Rule ID prefix must be declared in Scope: $RelativePath"
            }
            if ($null -ne $DeclaredPrefix -and
                $DeclaredPrefix -cne $Matches[1]) {
                throw "Multiple Rule ID prefixes are declared in $RelativePath."
            }
            $DeclaredPrefix = $Matches[1]
        }

        if ($Line -match '^- \*\*([A-Z][A-Z0-9-]*-[0-9]{3}) — ') {
            $Rules.Add([pscustomobject]@{
                    Id = $Matches[1]
                    Section = $Section
                    File = $RelativePath.Replace('\', '/')
                })
        }
    }

    if ($null -ne $DeclaredPrefix) {
        $Owners.Add([pscustomobject]@{
                Prefix = $DeclaredPrefix
                File = $RelativePath.Replace('\', '/')
            })
    }
}

$DuplicateIds = @($Rules | Group-Object Id | Where-Object Count -gt 1)
if ($DuplicateIds.Count -gt 0) {
    throw "Duplicate Rule IDs: $($DuplicateIds.Name -join ', ')"
}

$DuplicatePrefixes = @($Owners | Group-Object Prefix | Where-Object Count -gt 1)
if ($DuplicatePrefixes.Count -gt 0) {
    throw "Rule ID prefixes have multiple owners: $($DuplicatePrefixes.Name -join ', ')"
}

$OwnerFiles = @($Owners | Select-Object -ExpandProperty File)
$UnownedLocalFiles = @(
    $Rules |
        Where-Object {
            $_.File -like '*AGENTS.md' -and
            $_.Section -in @('Accepted', 'Open') -and
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
        throw "Prefix $($Owner.Prefix) has missing historical IDs: $($MissingIds -join ', ')"
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
        '[PASS] {0} Rule IDs are unique; {1} local prefixes have one owner and contiguous history.' -f
        $Rules.Count,
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
