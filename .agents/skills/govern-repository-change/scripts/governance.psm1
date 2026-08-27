$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repositoryModule = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\..\..\.github\rulesets\scripts\repository.psm1'
))
Import-Module $repositoryModule -Force

function Invoke-GovernanceNative {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    return Invoke-RepositoryNative -Executable $Executable -Arguments $Arguments
}

function Invoke-GovernanceCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    return Invoke-RepositoryCommand `
        -Executable $Executable `
        -Arguments $Arguments `
        -Operation $Operation
}

function Get-GitHubRepositoryFromRemote {
    param([string]$RemoteUrl)

    return Get-RepositoryFromGitHubRemote -RemoteUrl $RemoteUrl
}

function Get-GovernanceNormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Get-RepositoryNormalizedPath -Path $Path
}

function Get-GovernanceOrigin {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    return Get-RepositoryOrigin `
        -Git $Git `
        -RepositoryRoot $RepositoryRoot
}

function Get-GovernanceBranchTracking {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    return Get-RepositoryBranchTracking `
        -Git $Git `
        -RepositoryRoot $RepositoryRoot `
        -Branch $Branch
}

function Remove-GovernanceMarkdownNonSemanticContent {
    param([AllowNull()][string]$Body)

    $withoutComments = [regex]::Replace(
        [string]$Body,
        '(?s)<!--.*?(?:-->|\z)',
        ''
    )
    $semanticLines = [Collections.Generic.List[string]]::new()
    $fenceCharacter = $null
    $fenceLength = 0
    foreach ($line in @($withoutComments -split "`r?`n")) {
        if ($null -eq $fenceCharacter) {
            $opening = [regex]::Match(
                $line,
                '^[ ]{0,3}(?<fence>`{3,}|~{3,})'
            )
            if ($opening.Success) {
                $fence = $opening.Groups['fence'].Value
                $fenceCharacter = $fence.Substring(0, 1)
                $fenceLength = $fence.Length
                continue
            }
            [void]$semanticLines.Add($line)
            continue
        }

        $closingPattern = '^[ ]{0,3}' +
            [regex]::Escape($fenceCharacter) +
            "{$fenceLength,}[ `t]*$"
        if ($line -cmatch $closingPattern) {
            $fenceCharacter = $null
            $fenceLength = 0
        }
    }
    return $semanticLines.ToArray() -join "`n"
}

function Get-GovernanceChecklistErrors {
    param(
        [AllowNull()][string]$Content,
        [Parameter(Mandatory = $true)][string[]]$Items,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    $errors = [Collections.Generic.List[string]]::new()
    $semanticContent = Remove-GovernanceMarkdownNonSemanticContent `
        -Body $Content
    foreach ($item in $Items) {
        $pattern = '(?im)^[ ]{0,3}-[ \t]*\[[xX]\][ \t]+' +
            [regex]::Escape($item) + '[ \t]*$'
        if ($semanticContent -notmatch $pattern) {
            [void]$errors.Add("$Owner item is missing or incomplete: $item")
        }
    }
    if ($semanticContent -match '(?im)^[ ]{0,3}-[ \t]*\[[ \t]\][ \t]+') {
        [void]$errors.Add("$Owner contains an incomplete item.")
    }
    return $errors.ToArray()
}

function Test-GovernanceIssueReference {
    param(
        [AllowNull()][string]$Body,
        [Parameter(Mandatory = $true)][int]$IssueNumber
    )

    $semanticBody = Remove-GovernanceMarkdownNonSemanticContent -Body $Body
    $pattern = '(?m)^[ ]{0,3}Refs:[ \t]+#' +
        [regex]::Escape([string]$IssueNumber) + '[ \t]*$'
    return $semanticBody -cmatch $pattern
}

function Test-GovernanceClosingReference {
    param(
        [AllowNull()][string]$Body,
        [Parameter(Mandatory = $true)][int]$IssueNumber,
        [AllowNull()][string]$Repository
    )

    $semanticBody = Remove-GovernanceMarkdownNonSemanticContent -Body $Body
    $keywords = 'close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved'
    $escapedIssue = [regex]::Escape([string]$IssueNumber)
    $references = [Collections.Generic.List[string]]::new()
    [void]$references.Add("#$escapedIssue")
    if (-not [string]::IsNullOrWhiteSpace($Repository)) {
        $escapedRepository = [regex]::Escape($Repository.Trim())
        [void]$references.Add("$escapedRepository#$escapedIssue")
        [void]$references.Add(
            "https?://github\.com/$escapedRepository/issues/$escapedIssue"
        )
    }
    $pattern = '(?im)(?<![a-z])(?:' + $keywords +
        ')[ \t]*:?[ \t]+(?:' + ($references -join '|') +
        ')(?![a-z0-9])'
    return $semanticBody -match $pattern
}

function Get-GovernanceChangedPaths {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Files
    )

    $paths = [Collections.Generic.List[string]]::new()
    foreach ($file in $Files) {
        $filename = [string]$file.filename
        if (-not [string]::IsNullOrWhiteSpace($filename)) {
            [void]$paths.Add($filename)
        }
        if ([string]$file.status -ceq 'renamed') {
            $previousFilename = [string]$file.previous_filename
            if (-not [string]::IsNullOrWhiteSpace($previousFilename)) {
                [void]$paths.Add($previousFilename)
            }
        }
    }
    return $paths.ToArray()
}

function Test-GovernanceTrustRootPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return $Path.StartsWith(
        '.github/workflows/',
        [StringComparison]::Ordinal
    ) -or $Path -ceq (
        '.agents/skills/govern-repository-change/' +
        'scripts/governance.psm1'
    ) -or $Path -ceq (
        '.github/rulesets/scripts/repository.psm1'
    )
}

function Test-GovernanceMigrationAuthorization {
    param(
        [AllowNull()][string]$Action,
        [AllowNull()][string]$EventLabel,
        [AllowNull()][string]$Actor,
        [AllowNull()][string]$Owner,
        [Parameter(Mandatory = $true)][int]$RunAttempt,
        [Parameter(Mandatory = $true)][string]$RequiredLabel
    )

    return $RunAttempt -eq 1 -and
        $Action -ceq 'labeled' -and
        $EventLabel -ceq $RequiredLabel -and
        -not [string]::IsNullOrWhiteSpace($Actor) -and
        -not [string]::IsNullOrWhiteSpace($Owner) -and
        [string]::Equals(
            $Actor,
            $Owner,
            [StringComparison]::OrdinalIgnoreCase
        )
}

function Get-GovernanceMarkdownSection {
    param(
        [string]$Body,
        [string]$Heading,
        [int]$Level = 3
    )

    $semanticBody = Remove-GovernanceMarkdownNonSemanticContent -Body $Body
    $headingPattern = '^(?<marks>#{1,6})[ \t]+(?<title>.*?)[ \t]*$'
    $content = [Collections.Generic.List[string]]::new()
    $insideSection = $false
    foreach ($line in @($semanticBody -split "`n")) {
        $headingMatch = [regex]::Match($line, $headingPattern)
        if ($headingMatch.Success) {
            if ($insideSection) {
                if ($headingMatch.Groups['marks'].Value.Length -le $Level) {
                    break
                }
                [void]$content.Add($line)
                continue
            }
            if ($headingMatch.Groups['marks'].Value.Length -eq $Level -and
                [string]::Equals(
                $headingMatch.Groups['title'].Value,
                $Heading,
                [StringComparison]::Ordinal
            )) {
                $insideSection = $true
            }
            continue
        }
        if ($insideSection) {
            [void]$content.Add($line)
        }
    }
    if (-not $insideSection) {
        return $null
    }
    return ($content.ToArray() -join "`n").Trim()
}

function Test-GovernanceIssueContract {
    param([string]$Body)

    $errors = [Collections.Generic.List[string]]::new()
    foreach ($heading in @(
        'Outcome',
        'Reason',
        'Scope',
        'Non-goals',
        'Invariants',
        'Acceptance criteria',
        'Readiness'
    )) {
        $content = Get-GovernanceMarkdownSection -Body $Body -Heading $heading
        if ([string]::IsNullOrWhiteSpace($content) -or
            $content -ceq '_No response_') {
            [void]$errors.Add("Issue section '$heading' is missing or empty.")
        }
    }

    $readiness = Get-GovernanceMarkdownSection `
        -Body $Body `
        -Heading 'Readiness'
    $readinessItems = @(
        'The outcome is bounded enough for one branch and one PR.',
        'Unknowns and assumptions are explicit; implementation will not silently decide them.',
        'Version-controlled changes will begin only after an Issue-linked branch exists.'
    )
    foreach ($checklistError in @(Get-GovernanceChecklistErrors `
        -Content ([string]$readiness) `
        -Items $readinessItems `
        -Owner 'Issue Readiness')) {
        [void]$errors.Add($checklistError)
    }

    return $errors.ToArray()
}

function Test-GovernanceLinkedBranch {
    param(
        [string[]]$Output,
        [string]$Repository,
        [string]$Branch
    )

    $expectedPrefix = "/$Repository/tree/"
    foreach ($line in $Output) {
        $columns = ([string]$line).Trim() -split '\s+', 2
        if ($columns.Count -ne 2 -or $columns[0] -cne $Branch) {
            continue
        }
        try {
            $uri = [Uri]$columns[1]
            $path = [Uri]::UnescapeDataString($uri.AbsolutePath).TrimEnd('/')
            if ($uri.Scheme -ceq 'https' -and
                $uri.Host -ceq 'github.com' -and
                $path.StartsWith(
                    $expectedPrefix,
                    [StringComparison]::OrdinalIgnoreCase
                ) -and
                $path.Substring($expectedPrefix.Length) -ceq $Branch) {
                return $true
            }
        }
        catch {
            continue
        }
    }
    return $false
}

Export-ModuleMember -Function @(
    'Get-GovernanceChangedPaths',
    'Get-GovernanceChecklistErrors',
    'Get-GovernanceMarkdownSection',
    'Get-GovernanceBranchTracking',
    'Get-GovernanceNormalizedPath',
    'Get-GovernanceOrigin',
    'Get-GitHubRepositoryFromRemote',
    'Invoke-GovernanceCommand',
    'Invoke-GovernanceNative',
    'Test-GovernanceClosingReference',
    'Test-GovernanceIssueReference',
    'Test-GovernanceIssueContract',
    'Test-GovernanceLinkedBranch',
    'Test-GovernanceMigrationAuthorization',
    'Test-GovernanceTrustRootPath'
)
