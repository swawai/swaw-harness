$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repositoryModule = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\..\..\.github\rulesets\scripts\repository.psm1'
))
Import-Module $repositoryModule -Force

$script:manifestRelativePath = `
    '.agents/skills/govern-repository-change/ownership.json'
$script:manifestId = 'swaw.repository-change-governance'
$script:rulesetName = 'swaw-change-governance'
$script:rulesetPath = '.github/rulesets/swaw-change-governance.json'

function Assert-ManifestObject {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Owner,
        [Parameter(Mandatory = $true)][string[]]$Properties
    )

    if ($null -eq $Value -or $Value -isnot [PSCustomObject]) {
        throw "$Owner must be a JSON object."
    }
    $actual = @($Value.PSObject.Properties.Name)
    foreach ($name in $Properties) {
        if ($actual -cnotcontains $name) {
            throw "$Owner is missing property '$name'."
        }
    }
    foreach ($name in $actual) {
        if ($Properties -cnotcontains $name) {
            throw "$Owner contains unsupported property '$name'."
        }
    }
}

function Assert-ManifestPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Owner must not be empty."
    }
    if ($Path.Contains('\') -or [IO.Path]::IsPathRooted($Path) -or
        $Path -cmatch '^[A-Za-z]:') {
        throw "$Owner must be a repository-relative '/' path: '$Path'."
    }
    $segments = @($Path.Split([char[]]@('/')))
    if ($segments.Count -eq 0 -or @($segments | Where-Object {
        [string]::IsNullOrWhiteSpace($_) -or $_ -ceq '.' -or $_ -ceq '..'
    }).Count -gt 0) {
        throw "$Owner contains an unsafe path segment: '$Path'."
    }
}

function ConvertFrom-GovernanceOwnershipManifest {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$Owner
    )

    try {
        $manifest = $Json | ConvertFrom-Json
    }
    catch {
        throw "$Owner is not valid JSON: $($_.Exception.Message)"
    }
    Assert-ManifestObject $manifest $Owner @(
        'schema_version', 'id', 'versioned', 'local_git', 'github'
    )
    if (($manifest.schema_version -isnot [int] -and
        $manifest.schema_version -isnot [long]) -or
        [long]$manifest.schema_version -ne 1) {
        throw "$Owner schema_version must be 1."
    }
    if ([string]$manifest.id -cne $script:manifestId) {
        throw "$Owner id must be '$script:manifestId'."
    }
    Assert-ManifestObject $manifest.versioned "$Owner versioned" @(
        'exclusive_directories', 'required_files', 'retained_files',
        'removable_files', 'managed_blocks'
    )
    Assert-ManifestObject $manifest.local_git "$Owner local_git" @('settings')
    Assert-ManifestObject $manifest.github "$Owner github" @('rulesets')
    if (@($manifest.local_git.settings).Count -ne 0) {
        throw "$Owner local_git.settings is reserved for a later schema."
    }

    $seenPaths = @{}
    foreach ($entry in @(
        @($manifest.versioned.exclusive_directories | ForEach-Object {
            [pscustomobject]@{ Kind = 'directory'; Path = [string]$_ }
        })
        @($manifest.versioned.removable_files | ForEach-Object {
            [pscustomobject]@{ Kind = 'file'; Path = [string]$_ }
        })
        @($manifest.versioned.managed_blocks | ForEach-Object {
            Assert-ManifestObject $_ "$Owner managed block" @(
                'path', 'begin', 'end'
            )
            [pscustomobject]@{ Kind = 'block'; Path = [string]$_.path }
        })
    )) {
        Assert-ManifestPath $entry.Path "$Owner $($entry.Kind) path"
        $key = $entry.Path.ToLowerInvariant()
        if ($seenPaths.ContainsKey($key)) {
            throw (
                "$Owner path '$($entry.Path)' overlaps '$($seenPaths[$key])'."
            )
        }
        $seenPaths[$key] = $entry.Kind
    }

    $requiredPaths = @{}
    foreach ($pathValue in @($manifest.versioned.required_files)) {
        $path = [string]$pathValue
        Assert-ManifestPath $path "$Owner required file path"
        $key = $path.ToLowerInvariant()
        if ($requiredPaths.ContainsKey($key)) {
            throw "$Owner contains duplicate required file '$path'."
        }
        $requiredPaths[$key] = $true
        $insideOwnedDirectory = @(
            $manifest.versioned.exclusive_directories | Where-Object {
                $prefix = ([string]$_).TrimEnd('/') + '/'
                $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
            }
        ).Count -eq 1
        if (-not $insideOwnedDirectory) {
            throw "$Owner required file '$path' must be in one owned directory."
        }
    }

    $retainedPaths = @{}
    foreach ($pathValue in @($manifest.versioned.retained_files)) {
        $path = [string]$pathValue
        Assert-ManifestPath $path "$Owner retained file path"
        $key = $path.ToLowerInvariant()
        if ($retainedPaths.ContainsKey($key)) {
            throw "$Owner contains duplicate retained file '$path'."
        }
        if ($requiredPaths.ContainsKey($key) -or $seenPaths.ContainsKey($key)) {
            throw "$Owner retained file '$path' overlaps removable ownership."
        }
        $insideOwnedDirectory = @(
            $manifest.versioned.exclusive_directories | Where-Object {
                $prefix = ([string]$_).TrimEnd('/') + '/'
                $path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
            }
        ).Count -gt 0
        if ($insideOwnedDirectory) {
            throw "$Owner retained file '$path' must be outside owned directories."
        }
        $retainedPaths[$key] = $true
    }

    foreach ($block in @($manifest.versioned.managed_blocks)) {
        $begin = [string]$block.begin
        $end = [string]$block.end
        if ([string]::IsNullOrWhiteSpace($begin) -or
            [string]::IsNullOrWhiteSpace($end) -or
            $begin -ceq $end -or $begin.Contains("`n") -or
            $end.Contains("`n")) {
            throw "$Owner managed block markers must be distinct single lines."
        }
    }

    $rulesetNames = @{}
    $declaredFiles = @($manifest.versioned.removable_files | ForEach-Object {
        ([string]$_).ToLowerInvariant()
    })
    if (@($manifest.github.rulesets).Count -ne 1) {
        throw "$Owner must declare exactly one governance Ruleset."
    }
    foreach ($ruleset in @($manifest.github.rulesets)) {
        Assert-ManifestObject $ruleset "$Owner GitHub Ruleset" @(
            'name', 'ownership_token', 'desired_path'
        )
        $name = [string]$ruleset.name
        $token = [string]$ruleset.ownership_token
        $path = [string]$ruleset.desired_path
        Assert-ManifestPath $path "$Owner Ruleset desired_path"
        if ($name -cne $script:rulesetName -or
            $path -cne $script:rulesetPath) {
            throw "$Owner must pin the dedicated governance Ruleset identity."
        }
        if ($token -cnotmatch '^[0-9a-f]{32}$') {
            throw "$Owner Ruleset ownership_token must be 32 lowercase hex digits."
        }
        $nameKey = $name.ToLowerInvariant()
        if ($rulesetNames.ContainsKey($nameKey)) {
            throw "$Owner contains duplicate Ruleset name '$name'."
        }
        $rulesetNames[$nameKey] = $true
        if ($declaredFiles -cnotcontains $path.ToLowerInvariant()) {
            throw "$Owner Ruleset desired_path '$path' is not an owned file."
        }
    }
    return $manifest
}

function Get-GitObject {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $object = '{0}:{1}' -f @($Ref, $Path)
    $typeResult = Invoke-RepositoryNative `
        -Executable $Git `
        -Arguments @('-C', $RepositoryRoot, 'cat-file', '-t', $object)
    if ($typeResult.ExitCode -ne 0) {
        return $null
    }
    $content = $null
    if ([string]@($typeResult.Output)[-1] -ceq 'blob') {
        $content = @(Invoke-RepositoryCommand `
            -Executable $Git `
            -Arguments @('-C', $RepositoryRoot, 'show', $object) `
            -Operation "Read '$Path' from '$Ref'") -join "`n"
    }
    return [pscustomobject]@{
        Type = ([string]@($typeResult.Output)[-1]).Trim()
        Content = $content
    }
}

function Get-MarkerCount {
    param([string]$Content, [string]$Marker)

    return [regex]::Matches($Content, [regex]::Escape($Marker)).Count
}

function Get-GovernanceSourceState {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [string]$Ref = ''
    )

    $root = Get-RepositoryNormalizedPath -Path $RepositoryRoot
    if ([string]::IsNullOrWhiteSpace($Ref)) {
        $manifestPath = Join-Path $root `
            ($script:manifestRelativePath.Replace('/', '\'))
        if (-not [IO.File]::Exists($manifestPath)) {
            return [pscustomobject]@{
                State = 'absent'; Manifest = $null; Diagnostics = @()
            }
        }
        $manifestJson = [IO.File]::ReadAllText(
            $manifestPath,
            [Text.Encoding]::UTF8
        )
    }
    else {
        $manifestObject = Get-GitObject $Git $root $Ref `
            $script:manifestRelativePath
        if ($null -eq $manifestObject) {
            return [pscustomobject]@{
                State = 'absent'; Manifest = $null; Diagnostics = @()
            }
        }
        if ($manifestObject.Type -cne 'blob') {
            return [pscustomobject]@{
                State = 'invalid'; Manifest = $null
                Diagnostics = @('The ownership manifest is not a file.')
            }
        }
        $manifestJson = $manifestObject.Content
    }

    try {
        $manifest = ConvertFrom-GovernanceOwnershipManifest `
            -Json $manifestJson `
            -Owner 'Governance ownership manifest'
    }
    catch {
        return [pscustomobject]@{
            State = 'invalid'; Manifest = $null
            Diagnostics = @($_.Exception.Message)
        }
    }

    $missing = [Collections.Generic.List[string]]::new()
    $collisions = [Collections.Generic.List[string]]::new()
    foreach ($path in @($manifest.versioned.exclusive_directories)) {
        if ([string]::IsNullOrWhiteSpace($Ref)) {
            $absolute = Join-Path $root ([string]$path).Replace('/', '\')
            if (-not [IO.Directory]::Exists($absolute)) {
                if ([IO.File]::Exists($absolute)) {
                    [void]$collisions.Add("directory:$path")
                }
                else { [void]$missing.Add("directory:$path") }
            }
        }
        else {
            $item = Get-GitObject $Git $root $Ref ([string]$path)
            if ($null -eq $item) { [void]$missing.Add("directory:$path") }
            elseif ($item.Type -cne 'tree') {
                [void]$collisions.Add("directory:$path")
            }
        }
    }
    foreach ($path in @(
        @($manifest.versioned.required_files) +
        @($manifest.versioned.retained_files) +
        @($manifest.versioned.removable_files)
    )) {
        if ([string]::IsNullOrWhiteSpace($Ref)) {
            $absolute = Join-Path $root ([string]$path).Replace('/', '\')
            if (-not [IO.File]::Exists($absolute)) {
                if ([IO.Directory]::Exists($absolute)) {
                    [void]$collisions.Add("file:$path")
                }
                else { [void]$missing.Add("file:$path") }
            }
        }
        else {
            $item = Get-GitObject $Git $root $Ref ([string]$path)
            if ($null -eq $item) { [void]$missing.Add("file:$path") }
            elseif ($item.Type -cne 'blob') {
                [void]$collisions.Add("file:$path")
            }
        }
    }
    foreach ($block in @($manifest.versioned.managed_blocks)) {
        $path = [string]$block.path
        if ([string]::IsNullOrWhiteSpace($Ref)) {
            $absolute = Join-Path $root $path.Replace('/', '\')
            $content = if ([IO.File]::Exists($absolute)) {
                [IO.File]::ReadAllText($absolute, [Text.Encoding]::UTF8)
            }
            else { $null }
        }
        else {
            $item = Get-GitObject $Git $root $Ref $path
            $content = if ($null -ne $item -and $item.Type -ceq 'blob') {
                $item.Content
            }
            else { $null }
        }
        if ($null -eq $content) {
            [void]$missing.Add("block:$path")
        }
        elseif ((Get-MarkerCount $content ([string]$block.begin)) -ne 1 -or
            (Get-MarkerCount $content ([string]$block.end)) -ne 1 -or
            $content.IndexOf([string]$block.begin) -ge
                $content.IndexOf([string]$block.end)) {
            [void]$collisions.Add("block:$path")
        }
    }

    $state = if ($collisions.Count -gt 0) { 'collision' }
        elseif ($missing.Count -gt 0) { 'partial' }
        else { 'installed' }
    return [pscustomobject]@{
        State = $state
        Manifest = $manifest
        Diagnostics = @($missing) + @($collisions)
    }
}

function Get-GovernanceRulesetRemoteName {
    param([Parameter(Mandatory = $true)]$Declaration)

    return '{0}{1}' -f @(
        (Get-GovernanceRulesetRemotePrefix -Declaration $Declaration),
        [string]$Declaration.ownership_token
    )
}

function Get-GovernanceRulesetRemotePrefix {
    param([Parameter(Mandatory = $true)]$Declaration)

    return '{0}--' -f [string]$Declaration.name
}

Export-ModuleMember -Function @(
    'ConvertFrom-GovernanceOwnershipManifest',
    'Get-GovernanceRulesetRemoteName',
    'Get-GovernanceRulesetRemotePrefix',
    'Get-GovernanceSourceState'
)
