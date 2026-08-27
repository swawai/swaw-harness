[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaseSha,

    [Parameter(Mandatory = $true)]
    [string]$HeadSha,

    [string]$RepositoryRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1

function Invoke-ReviewGit {
    param([string[]]$Arguments)

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $script:git.Source -C $script:repositoryRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join ' ')"
    }
    return $output
}

function Invoke-ReviewGitNul {
    param([string[]]$Arguments)

    foreach ($argument in $Arguments) {
        if ($argument -cnotmatch '^[A-Za-z0-9._/:={}^~-]+$') {
            throw "Unsafe binary git argument: '$argument'"
        }
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $script:git.Source
    $startInfo.WorkingDirectory = $script:repositoryRoot
    $startInfo.Arguments = $Arguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $output = [IO.MemoryStream]::new()
        $process.StandardOutput.BaseStream.CopyTo($output)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments -join ' ') failed: $errorText"
        }
        $bytes = $output.ToArray()
    }
    finally {
        $process.Dispose()
    }

    if ($bytes.Length -eq 0) { return @() }
    if ($bytes[$bytes.Length - 1] -ne 0) {
        throw 'NUL-delimited git output was not terminated.'
    }

    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $paths = [Collections.Generic.List[string]]::new()
    $start = 0
    for ($index = 0; $index -lt $bytes.Length; $index++) {
        if ($bytes[$index] -ne 0) { continue }
        if ($index -eq $start) {
            throw 'NUL-delimited git output contained an empty path.'
        }
        $paths.Add($encoding.GetString($bytes, $start, $index - $start))
        $start = $index + 1
    }
    return @($paths)
}

function Get-OrdinalUnique {
    param([string[]]$Values)

    $seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $result = [Collections.Generic.List[string]]::new()
    foreach ($value in $Values) {
        if ($seen.Add($value)) { $result.Add($value) }
    }
    return @($result)
}

function Resolve-ReviewCommit {
    param([string]$Revision)

    $resolved = @(Invoke-ReviewGit @(
        'rev-parse', '--verify', "$Revision^{commit}"
    ))
    return [string]$resolved[-1]
}

function Get-PolicyPaths {
    param([string]$Revision)

    return @(
        Invoke-ReviewGitNul @('ls-tree', '-rz', '--name-only', $Revision) |
            Where-Object {
                $_ -ceq 'AGENTS.md' -or $_.EndsWith(
                    '/AGENTS.md',
                    [StringComparison]::Ordinal
                )
            }
    )
}

function Test-PolicyApplies {
    param([string]$PolicyPath, [string]$ChangedPath)

    if ($PolicyPath -ceq 'AGENTS.md') { return $true }
    $directory = [IO.Path]::GetDirectoryName($PolicyPath).Replace('\', '/')
    return $ChangedPath -ceq $PolicyPath -or
        $ChangedPath.StartsWith(
            $directory + '/',
            [StringComparison]::Ordinal
        )
}

$resolvedBase = Resolve-ReviewCommit $BaseSha
$resolvedHead = Resolve-ReviewCommit $HeadSha
$changedPaths = @(Get-OrdinalUnique @(
    Invoke-ReviewGitNul @(
        'diff', '--name-only', '--no-renames', '-z',
        "$resolvedBase..$resolvedHead", '--'
    )
))
if ($changedPaths.Count -eq 0) {
    throw 'The protected-review range contains no changed paths.'
}

$basePolicies = @(Get-PolicyPaths $resolvedBase)
$headPolicies = @(Get-PolicyPaths $resolvedHead)
$allPolicies = @(Get-OrdinalUnique @($basePolicies + $headPolicies))

foreach ($policyPath in $allPolicies) {
    $applicable = @($changedPaths | Where-Object {
        Test-PolicyApplies $policyPath $_
    }).Count -gt 0
    if (-not $applicable) { continue }

    [pscustomobject]@{
        Path = $policyPath
        BaseExists = @($basePolicies | Where-Object {
            $_ -ceq $policyPath
        }).Count -eq 1
        HeadExists = @($headPolicies | Where-Object {
            $_ -ceq $policyPath
        }).Count -eq 1
    }
}
