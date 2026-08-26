$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'repository.psm1') -Force

function Get-GitHubMainOid {
    param(
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    $output = @(Invoke-RepositoryCommand `
        -Executable $Ghswaw `
        -Arguments @(
            'api',
            '-H', 'Accept: application/vnd.github+json',
            '-H', 'X-GitHub-Api-Version: 2026-03-10',
            '--method', 'GET',
            "repos/$Repository/git/ref/heads/main"
        ) `
        -Operation 'Read GitHub main ref')
    try {
        $response = ($output -join "`n") | ConvertFrom-Json
        $oid = [string]$response.object.sha
    }
    catch {
        throw "GitHub main ref response is invalid: $($_.Exception.Message)"
    }
    if ($oid -cnotmatch '^[0-9a-fA-F]{40}$') {
        throw 'GitHub main ref response does not contain a full commit OID.'
    }
    return $oid.ToLowerInvariant()
}

function Assert-GovernanceControlPlaneContext {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$Ghswaw,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    $branch = @(Invoke-RepositoryCommand `
        -Executable $Git `
        -Arguments @('-C', $RepositoryRoot, 'branch', '--show-current') `
        -Operation 'Resolve control-plane branch')[-1].Trim()
    if ($branch -cne 'main') {
        throw 'Control-plane mutations must run from main.'
    }
    $worktree = @(Invoke-RepositoryCommand `
        -Executable $Git `
        -Arguments @(
            '-C', $RepositoryRoot,
            'status', '--porcelain=v1', '--untracked-files=all'
        ) `
        -Operation 'Inspect control-plane worktree')
    if ($worktree.Count -gt 0) {
        throw 'Control-plane mutations require a clean worktree.'
    }
    $head = @(Invoke-RepositoryCommand `
        -Executable $Git `
        -Arguments @('-C', $RepositoryRoot, 'rev-parse', 'HEAD') `
        -Operation 'Resolve control-plane HEAD')[-1].Trim().ToLowerInvariant()
    $tracking = @(Invoke-RepositoryCommand `
        -Executable $Git `
        -Arguments @('-C', $RepositoryRoot, 'rev-parse', 'origin/main') `
        -Operation 'Resolve origin/main')[-1].Trim().ToLowerInvariant()
    $remote = Get-GitHubMainOid `
        -Ghswaw $Ghswaw `
        -Repository $Repository
    if ($head -cne $tracking -or $head -cne $remote) {
        throw (
            'main, origin/main, and the GitHub main ref must identify the ' +
            'same commit before a control-plane mutation.'
        )
    }
}

Export-ModuleMember -Function @(
    'Assert-GovernanceControlPlaneContext',
    'Get-GitHubMainOid'
)
