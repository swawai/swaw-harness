[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')]
    [string]$Slug,

    [Parameter(Mandatory = $true)]
    [string]$Outcome,

    [Parameter(Mandatory = $true)]
    [string]$Reason,

    [Parameter(Mandatory = $true)]
    [string]$Scope,

    [Parameter(Mandatory = $true)]
    [string]$NonGoals,

    [Parameter(Mandatory = $true)]
    [string]$Invariants,

    [Parameter(Mandatory = $true)]
    [string[]]$AcceptanceCriteria,

    [ValidatePattern('^[a-z][a-z0-9-]*$')]
    [string]$Actor = 'codex',

    [string]$OpenQuestions = 'None.',

    [string]$References = 'None.',

    [string]$RepositoryRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$baseBranch = 'main'
Import-Module (Join-Path $PSScriptRoot 'governance.psm1') -Force

function Assert-GovernedText {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [switch]$SingleLine
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must not be empty."
    }
    if ($SingleLine -and $Value -match '[\r\n]') {
        throw "$Name must be a single line."
    }
    if ($Value -match '(?m)^###\s') {
        throw "$Name must not introduce an Issue section heading."
    }
}

foreach ($field in @{
    Title = $Title
    Outcome = $Outcome
    Reason = $Reason
    Scope = $Scope
    'Non-goals' = $NonGoals
    Invariants = $Invariants
    'Open questions' = $OpenQuestions
    References = $References
}.GetEnumerator()) {
    Assert-GovernedText -Name $field.Key -Value $field.Value
}
Assert-GovernedText -Name 'Title' -Value $Title -SingleLine

if ($AcceptanceCriteria.Count -eq 0) {
    throw 'AcceptanceCriteria must contain at least one item.'
}
$criteria = @($AcceptanceCriteria | ForEach-Object {
    Assert-GovernedText -Name 'Acceptance criterion' -Value $_ -SingleLine
    $_.Trim()
})

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Join-Path $PSScriptRoot '..\..\..\..'
}
$RepositoryRoot = Get-GovernanceNormalizedPath -Path $RepositoryRoot

$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$ghswaw = Get-Command ghswaw -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
if ($null -eq $ghswaw) {
    throw 'ghswaw was not found as an application.'
}

$actualRootOutput = @(Invoke-GovernanceCommand `
    -Executable $git.Source `
    -Arguments @('-C', $RepositoryRoot, 'rev-parse', '--show-toplevel') `
    -Operation 'Resolve repository root')
$actualRoot = Get-GovernanceNormalizedPath -Path $actualRootOutput[-1].Trim()
if (-not $actualRoot.Equals(
    $RepositoryRoot,
    [StringComparison]::OrdinalIgnoreCase
)) {
    throw "RepositoryRoot must be the worktree root: $actualRoot"
}

Push-Location -LiteralPath $RepositoryRoot
try {
    $worktree = @(Invoke-GovernanceCommand `
        -Executable $git.Source `
        -Arguments @('status', '--porcelain=v1', '--untracked-files=all') `
        -Operation 'Inspect worktree')
    if ($worktree.Count -gt 0) {
        throw 'Start requires a clean worktree; preserve or finish existing work first.'
    }

    $branchOutput = @(Invoke-GovernanceCommand `
        -Executable $git.Source `
        -Arguments @('branch', '--show-current') `
        -Operation 'Read current branch')
    $branch = $branchOutput[-1].Trim()
    if ($branch -cne $baseBranch) {
        throw "Start requires branch '$baseBranch'; current branch is '$branch'."
    }

    $origin = Get-GovernanceOrigin `
        -Git $git.Source `
        -RepositoryRoot $RepositoryRoot
    $repository = $origin.Repository

    [void](Invoke-GovernanceCommand `
        -Executable $ghswaw.Source `
        -Arguments @('.doctor') `
        -Operation 'Validate ghswaw')

    $acceptanceText = @($criteria | ForEach-Object { "- [ ] $_" }) -join "`n"
    $issueBody = @"
### Outcome

$($Outcome.Trim())

### Reason

$($Reason.Trim())

### Scope

$($Scope.Trim())

### Non-goals

$($NonGoals.Trim())

### Invariants

$($Invariants.Trim())

### Acceptance criteria

$acceptanceText

### Open questions

$($OpenQuestions.Trim())

### References

$($References.Trim())

### Readiness

- [x] The outcome is bounded enough for one branch and one PR.
- [x] Unknowns and assumptions are explicit; implementation will not silently decide them.
- [x] Version-controlled changes will begin only after an Issue-linked branch exists.
"@
    $issueBody = $issueBody.Trim() + "`n"
    $contractErrors = @(Test-GovernanceIssueContract -Body $issueBody)
    if ($contractErrors.Count -gt 0) {
        throw (
            'Generated Issue does not satisfy the governance contract: ' +
            ($contractErrors -join ' ')
        )
    }

    if (-not $PSCmdlet.ShouldProcess(
        $repository,
        "Create Issue '$Title' and its linked branch from '$baseBranch'"
    )) {
        return [pscustomobject][ordered]@{
            State = 'planned'
            Repository = $repository
            BaseBranch = $baseBranch
            IssueNumber = $null
            IssueUrl = $null
            Branch = "$Actor/<issue-id>-$Slug"
        }
    }

    $payloadPath = [IO.Path]::GetTempFileName()
    try {
        $payload = [ordered]@{
            title = $Title.Trim()
            body = $issueBody
        } | ConvertTo-Json -Depth 3
        [IO.File]::WriteAllText(
            $payloadPath,
            $payload,
            [Text.UTF8Encoding]::new($false)
        )
        try {
            $issueOutput = Invoke-GovernanceCommand `
                -Executable $ghswaw.Source `
                -Arguments @(
                    'api', '--method', 'POST',
                    "repos/$repository/issues",
                    '--input', $payloadPath
                ) `
                -Operation 'Create GitHub Issue'
        }
        catch {
            throw (
                'The Issue creation result is unknown. Do not retry automatically; ' +
                "inspect $repository on GitHub first. $($_.Exception.Message)"
            )
        }
    }
    finally {
        try {
            [IO.File]::Delete($payloadPath)
        }
        catch {
            Write-Warning -WarningAction Continue -Message (
                "Temporary Issue payload cleanup failed at '$payloadPath'. " +
                "Remove that file manually. $($_.Exception.Message)"
            )
        }
    }

    try {
        $issue = ($issueOutput -join "`n") | ConvertFrom-Json
        $issueNumber = [int]$issue.number
        $issueUrl = [string]$issue.html_url
        if ($issueNumber -le 0 -or [string]::IsNullOrWhiteSpace($issueUrl)) {
            throw 'Issue response did not contain number and html_url.'
        }
    }
    catch {
        throw (
            'GitHub may have created the Issue, but its response was invalid. ' +
            "Do not retry automatically; inspect $repository first. " +
            $_.Exception.Message
        )
    }

    $linkedBranch = "$Actor/$issueNumber-$Slug"
    try {
        [void](Invoke-GovernanceCommand `
            -Executable $ghswaw.Source `
            -Arguments @(
                'issue', 'develop', [string]$issueNumber,
                '--repo', $repository,
                '--base', $baseBranch,
                '--name', $linkedBranch,
                '--checkout'
            ) `
            -Operation 'Create linked branch')
    }
    catch {
        throw (
            "Issue #$issueNumber was created at $issueUrl, but linked branch " +
            "creation failed. Do not create another Issue or retry blindly. " +
            "Inspect the Issue's linked branches and the remote branch " +
            "'$linkedBranch' before choosing a recovery action. " +
            $_.Exception.Message
        )
    }

    $selectedBranchOutput = @(Invoke-GovernanceCommand `
        -Executable $git.Source `
        -Arguments @('branch', '--show-current') `
        -Operation 'Verify linked branch')
    $selectedBranch = $selectedBranchOutput[-1].Trim()
    if ($selectedBranch -cne $linkedBranch) {
        throw (
            "Issue #$issueNumber and branch '$linkedBranch' were created, but " +
            "the checked-out branch is '$selectedBranch'. Stop and inspect the worktree."
        )
    }

    [pscustomobject][ordered]@{
        State = 'active'
        Repository = $repository
        BaseBranch = $baseBranch
        IssueNumber = $issueNumber
        IssueUrl = $issueUrl
        Branch = $linkedBranch
    }
}
finally {
    Pop-Location
}
