$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Invoke-RepositoryNative {
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

function Invoke-RepositoryCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    $result = Invoke-RepositoryNative `
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

function Get-RepositoryFromGitHubRemote {
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

function Get-RepositoryNormalizedPath {
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

function Get-RepositoryOrigin {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $fetchUrls = @(Invoke-RepositoryCommand `
        -Executable $Git `
        -Arguments @(
            '-C', $RepositoryRoot,
            'remote', 'get-url', '--all', 'origin'
        ) `
        -Operation 'Resolve origin fetch URLs')
    $pushUrls = @(Invoke-RepositoryCommand `
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
        $candidate = Get-RepositoryFromGitHubRemote -RemoteUrl $entry.Url
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
                'Origin fetch and push URLs must identify one repository; ' +
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

function Get-RepositoryBranchTracking {
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
        $remoteResult = Invoke-RepositoryNative `
            -Executable $Git `
            -Arguments @(
                '-C', $RepositoryRoot,
                'config', '--get', "branch.$Branch.remote"
            )
        $mergeResult = Invoke-RepositoryNative `
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
                $refResult = Invoke-RepositoryNative `
                    -Executable $Git `
                    -Arguments @(
                        '-C', $RepositoryRoot,
                        'show-ref', '--verify', '--quiet', $upstreamRef
                    )
                $refExists = $refResult.ExitCode -eq 0
                if ($refExists) {
                    $countOutput = @(Invoke-RepositoryCommand `
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

Export-ModuleMember -Function @(
    'Get-RepositoryFromGitHubRemote',
    'Get-RepositoryBranchTracking',
    'Get-RepositoryNormalizedPath',
    'Get-RepositoryOrigin',
    'Invoke-RepositoryCommand',
    'Invoke-RepositoryNative'
)
