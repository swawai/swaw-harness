$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Invoke-GovernanceNative {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $Executable @Arguments 2>&1)
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject][ordered]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

function Invoke-GovernanceCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $result = Invoke-GovernanceNative `
        -Executable $Executable `
        -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        $detail = (@($result.Output | ForEach-Object {
            [string]$_
        }) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "exit code $($result.ExitCode)"
        }
        throw "$Operation failed: $detail"
    }

    return @($result.Output | ForEach-Object { [string]$_ })
}

function Get-GitHubRepositoryFromRemote {
    param([string]$RemoteUrl)

    $value = $RemoteUrl.Trim()
    $matchedPrefix = $false
    foreach ($prefix in @(
        'git@github.com:',
        'ssh://git@github.com/',
        'https://github.com/'
    )) {
        if ($value.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $value = $value.Substring($prefix.Length)
            $matchedPrefix = $true
            break
        }
    }
    if (-not $matchedPrefix) {
        return $null
    }
    $value = $value.TrimEnd('/')
    if ($value.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }
    if ($value -cmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        return $value
    }
    return $null
}

function Get-GovernanceNormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $pathRoot = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $pathRoot.Length) {
        return $fullPath.TrimEnd(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
    }
    return $fullPath
}

function Get-GovernanceOrigin {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $fetchUrls = @(Invoke-GovernanceCommand `
        -Executable $Git `
        -Arguments @(
            '-C', $RepositoryRoot,
            'remote', 'get-url', '--all', 'origin'
        ) `
        -Operation 'Resolve origin fetch URLs')
    $pushUrls = @(Invoke-GovernanceCommand `
        -Executable $Git `
        -Arguments @(
            '-C', $RepositoryRoot,
            'remote', 'get-url', '--push', '--all', 'origin'
        ) `
        -Operation 'Resolve origin push URLs')
    $fetchUrls = @($fetchUrls | ForEach-Object { ([string]$_).Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $pushUrls = @($pushUrls | ForEach-Object { ([string]$_).Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($fetchUrls.Count -eq 0 -or $pushUrls.Count -eq 0) {
        throw 'Origin must declare at least one fetch URL and one push URL.'
    }

    $repository = $null
    foreach ($entry in @(
        @($fetchUrls | ForEach-Object {
            [pscustomobject]@{ Kind = 'fetch'; Url = $_ }
        })
        @($pushUrls | ForEach-Object {
            [pscustomobject]@{ Kind = 'push'; Url = $_ }
        })
    )) {
        $candidate = Get-GitHubRepositoryFromRemote -RemoteUrl $entry.Url
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            throw (
                "Origin $($entry.Kind) URL is not an explicit github.com " +
                'repository URL; inspect the local remote configuration.'
            )
        }
        if ($null -eq $repository) {
            $repository = $candidate
        }
        elseif (-not [string]::Equals(
            $repository,
            $candidate,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw (
                "Origin fetch and push URLs must identify one repository; " +
                "found '$repository' and '$candidate'."
            )
        }
    }

    return [pscustomobject][ordered]@{
        Repository = $repository
        FetchUrls = $fetchUrls
        PushUrls = $pushUrls
    }
}

function Get-GovernanceBranchTracking {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Branch
    )

    $upstream = $null
    $upstreamRef = $null
    $refExists = $false
    $ahead = $null
    $behind = $null
    if ($Branch -cne '(detached)') {
        $remoteResult = Invoke-GovernanceNative `
            -Executable $Git `
            -Arguments @(
                '-C', $RepositoryRoot,
                'config', '--get', "branch.$Branch.remote"
            )
        $mergeResult = Invoke-GovernanceNative `
            -Executable $Git `
            -Arguments @(
                '-C', $RepositoryRoot,
                'config', '--get', "branch.$Branch.merge"
            )
        if ($remoteResult.ExitCode -eq 0 -and $mergeResult.ExitCode -eq 0) {
            $remote = ([string](@($remoteResult.Output)[-1])).Trim()
            $merge = ([string](@($mergeResult.Output)[-1])).Trim()
            if ($merge.StartsWith('refs/heads/', [StringComparison]::Ordinal)) {
                $upstreamBranch = $merge.Substring('refs/heads/'.Length)
                $upstream = if ($remote -ceq '.') {
                    $upstreamBranch
                }
                else {
                    "$remote/$upstreamBranch"
                }
                $upstreamRef = if ($remote -ceq '.') {
                    "refs/heads/$upstreamBranch"
                }
                else {
                    "refs/remotes/$remote/$upstreamBranch"
                }
                $refResult = Invoke-GovernanceNative `
                    -Executable $Git `
                    -Arguments @(
                        '-C', $RepositoryRoot,
                        'show-ref', '--verify', '--quiet', $upstreamRef
                    )
                $refExists = $refResult.ExitCode -eq 0
                if ($refExists) {
                    $countOutput = @(Invoke-GovernanceCommand `
                        -Executable $Git `
                        -Arguments @(
                            '-C', $RepositoryRoot,
                            'rev-list', '--left-right', '--count',
                            "$upstream...HEAD"
                        ) `
                        -Operation 'Compare with upstream branch')
                    $counts = $countOutput[-1] -split '\s+'
                    if ($counts.Count -eq 2) {
                        $behind = [int]$counts[0]
                        $ahead = [int]$counts[1]
                    }
                }
            }
        }
    }

    return [pscustomobject][ordered]@{
        Upstream = $upstream
        Ref = $upstreamRef
        RefExists = $refExists
        Ahead = $ahead
        Behind = $behind
    }
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
        $pattern = '(?im)^[ ]{0,3}-[ `t]*\[[xX]\][ `t]+' +
            [regex]::Escape($item) + '[ `t]*$'
        if ($semanticContent -notmatch $pattern) {
            [void]$errors.Add("$Owner item is missing or incomplete: $item")
        }
    }
    if ($semanticContent -match '(?im)^[ ]{0,3}-[ `t]*\[[ `t]\][ `t]+') {
        [void]$errors.Add("$Owner contains an incomplete item.")
    }
    return $errors.ToArray()
}

function Test-GovernanceClosingReference {
    param(
        [AllowNull()][string]$Body,
        [Parameter(Mandatory = $true)][int]$IssueNumber
    )

    $semanticBody = Remove-GovernanceMarkdownNonSemanticContent -Body $Body
    $pattern = '(?im)^[ ]{0,3}Closes[ `t]+#' +
        [regex]::Escape([string]$IssueNumber) + '[ `t]*$'
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
    )
}

function Get-GovernanceMarkdownSection {
    param(
        [string]$Body,
        [string]$Heading,
        [int]$Level = 3
    )

    $semanticBody = Remove-GovernanceMarkdownNonSemanticContent -Body $Body
    $headingPattern = '^(?<marks>#{1,6})[ `t]+(?<title>.*?)[ `t]*$'
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
    'Test-GovernanceIssueContract',
    'Test-GovernanceLinkedBranch',
    'Test-GovernanceTrustRootPath'
)
