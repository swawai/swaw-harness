Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')
. (Join-Path $PSScriptRoot '..\builder\filesystem.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$script:SwawHarnessModuleSchema = 'swaw.harness.module/v1'

function Assert-SwawHarnessModuleDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item -or -not $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must be a regular directory: $Path"
    }
    return [string]$Item.FullName
}

function Get-SwawHarnessModuleIdSegments {
    param([Parameter(Mandatory = $true)][string]$ModuleId)

    [string[]]$Segments = @($ModuleId.Split('/'))
    if ($Segments.Count -ne 3) {
        throw "ModuleId must contain Publisher/Group/Module: $ModuleId"
    }
    foreach ($Segment in $Segments) {
        if ($Segment -cnotmatch '^[a-z0-9][a-z0-9._+-]*$') {
            throw "ModuleId contains an invalid segment: $ModuleId"
        }
    }
    return $Segments
}

function Initialize-SwawHarnessCanonicalModuleDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Segment,
        [Parameter(Mandatory = $true)][string]$Description
    )

    [void](Assert-SwawHarnessModuleDirectory `
        -Path $Parent `
        -Description "$Description parent")
    $MatchingItems = @(Get-ChildItem -LiteralPath $Parent -Force | Where-Object {
        [string]::Equals(
            [string]$_.Name,
            $Segment,
            [StringComparison]::OrdinalIgnoreCase
        )
    })
    if ($MatchingItems.Count -gt 1) {
        throw "$Description has ambiguous case variants below: $Parent"
    }
    if ($MatchingItems.Count -eq 1) {
        if ([string]$MatchingItems[0].Name -cne $Segment) {
            throw (
                "$Description has non-canonical name '$($MatchingItems[0].Name)'; " +
                "expected '$Segment': $($MatchingItems[0].FullName)"
            )
        }
        return Assert-SwawHarnessModuleDirectory `
            -Path ([string]$MatchingItems[0].FullName) `
            -Description $Description
    }

    $Path = Join-Path $Parent $Segment
    [void][IO.Directory]::CreateDirectory($Path)
    $Item = Get-Item -LiteralPath $Path -Force
    if ([string]$Item.Name -cne $Segment) {
        throw (
            "$Description has non-canonical name '$($Item.Name)'; " +
            "expected '$Segment': $($Item.FullName)"
        )
    }
    return Assert-SwawHarnessModuleDirectory `
        -Path ([string]$Item.FullName) `
        -Description $Description
}

function Assert-SwawHarnessModuleVersion {
    param([Parameter(Mandatory = $true)][string]$Version)

    if ($Version -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "Module Version must be exact MAJOR.MINOR.PATCH: $Version"
    }
    return $Version
}

function Read-SwawHarnessModuleRelease {
    param(
        [Parameter(Mandatory = $true)][string]$ReleaseRoot,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$SourceArtifact,
        [Parameter(Mandatory = $true)][string]$ModulesRoot
    )

    $ReleaseRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $ReleaseRoot `
        -Root $ModulesRoot `
        -Activity 'reading an Admin Module Release'
    [void](Assert-SwawHarnessModuleDirectory `
        -Path $ReleaseRoot `
        -Description 'Module Release root')
    [string[]]$ExpectedNames = @(
        'swaw-harness.module.json',
        [string]$Contract.ProductBinary
    )
    [string[]]$ActualNames = @(
        Get-ChildItem -LiteralPath $ReleaseRoot -Force |
            ForEach-Object { [string]$_.Name }
    )
    if ($ActualNames.Count -ne $ExpectedNames.Count) {
        throw "Module Release membership is invalid: $ReleaseRoot"
    }
    foreach ($Name in $ExpectedNames) {
        if ($ActualNames -cnotcontains $Name) {
            throw "Module Release membership is invalid: $ReleaseRoot"
        }
    }

    $ManifestPath = Join-Path $ReleaseRoot 'swaw-harness.module.json'
    $Manifest = Read-SwawHarnessJsonFile `
        -Path $ManifestPath `
        -Description 'Module Release manifest'
    Assert-SwawHarnessObjectFields `
        -Value $Manifest `
        -Expected @(
            'schema', 'module', 'version', 'platformTargetId', 'executable'
        ) `
        -Description 'Module Release manifest'
    Assert-SwawHarnessObjectFields `
        -Value $Manifest.executable `
        -Expected @('name', 'length', 'sha256') `
        -Description 'Module Release executable record'
    $ExecutablePath = Resolve-SwawHarnessChildPath `
        -Root $ReleaseRoot `
        -RelativePath ([string]$Contract.ProductBinary) `
        -Description 'Module Release executable'
    $Executable = Assert-SwawHarnessRegularFile `
        -Path $ExecutablePath `
        -Description 'Module Release executable' `
        -MaximumBytes ([long]$Contract.MaximumBytes)
    $Sha256 = Get-SwawHarnessFileSha256 -Path $ExecutablePath
    if ([string]$Manifest.schema -cne $script:SwawHarnessModuleSchema -or
        [string]$Manifest.module -cne [string]$Contract.ModuleId -or
        [string]$Manifest.version -cne [string]$Contract.ModuleVersion -or
        [string]$Manifest.platformTargetId -cne
            [string]$Contract.PlatformTargetId -or
        [string]$Manifest.executable.name -cne
            [string]$Contract.ProductBinary -or
        [long]$Manifest.executable.length -ne [long]$Executable.Length -or
        [string]$Manifest.executable.sha256 -cne $Sha256 -or
        [long]$SourceArtifact.Length -ne [long]$Executable.Length -or
        [string]$SourceArtifact.Sha256 -cne $Sha256) {
        throw "Module Release validation failed: $ReleaseRoot"
    }

    return [pscustomobject][ordered]@{
        ModuleId = [string]$Contract.ModuleId
        Version = [string]$Contract.ModuleVersion
        PlatformTargetId = [string]$Contract.PlatformTargetId
        Root = $ReleaseRoot
        ManifestPath = $ManifestPath
        ExecutablePath = $ExecutablePath
        Length = [long]$Executable.Length
        Sha256 = $Sha256
    }
}

function Publish-SwawHarnessWindowsCoreModules {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$BootstrapRelease
    )

    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $PSScriptRoot '..\contract.json')
    $Contracts = @(Read-SwawHarnessWindowsCoreContracts `
        -Path (Join-Path $PSScriptRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId)
    if ([string]$BootstrapRelease.PlatformTargetId -cne
        [string]$PlatformContract.PlatformTargetId) {
        throw 'Bootstrap Release target does not match Module publication target.'
    }

    $HarnessRoot = Assert-SwawHarnessModuleDirectory `
        -Path ([string]$Context.HarnessRoot) `
        -Description 'HarnessRoot'
    $DataHome = Assert-SwawHarnessModuleDirectory `
        -Path (Join-Path $HarnessRoot 'data') `
        -Description 'DataHome'
    $AdminRoot = Assert-SwawHarnessModuleDirectory `
        -Path (Join-Path $DataHome 'admin') `
        -Description 'Admin EntryRoot'
    $SkillMapRoot = Assert-SwawHarnessModuleDirectory `
        -Path (Join-Path $AdminRoot 'map') `
        -Description 'Admin Skill Map root'
    [void](Assert-SwawHarnessModuleDirectory `
        -Path (Join-Path $SkillMapRoot 'core') `
        -Description 'Admin Core Skill Map')
    $ModulesRoot = Join-Path $AdminRoot 'modules'
    [void][IO.Directory]::CreateDirectory($ModulesRoot)
    $ModulesRoot = Assert-SwawHarnessModuleDirectory `
        -Path $ModulesRoot `
        -Description 'Admin module root'

    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $ModulesRoot (
            ".publish-$($PlatformContract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $ModulesRoot `
        -TimeoutSeconds 1800
    try {
        foreach ($WorkItem in Get-ChildItem -LiteralPath $ModulesRoot -Force) {
            if ([string]$WorkItem.Name -cmatch
                '^\.publish-[a-f0-9]{32}\.tmp$') {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path ([string]$WorkItem.FullName) `
                    -ControlledRoot $ModulesRoot `
                    -Activity 'cleaning interrupted Module publication'
            }
        }

        $Published = [Collections.Generic.List[object]]::new()
        foreach ($Contract in $Contracts) {
            [string[]]$Segments = Get-SwawHarnessModuleIdSegments `
                -ModuleId ([string]$Contract.ModuleId)
            $Version = Assert-SwawHarnessModuleVersion `
                -Version ([string]$Contract.ModuleVersion)
            $SourceArtifacts = @($BootstrapRelease.Artifacts | Where-Object {
                [string]$_.Name -ceq [string]$Contract.ProductBinary
            })
            if ($SourceArtifacts.Count -ne 1) {
                throw (
                    'Bootstrap Release does not contain exactly one module ' +
                    "artifact: $($Contract.ProductBinary)"
                )
            }
            $SourceArtifact = $SourceArtifacts[0]
            $ModuleParent = $ModulesRoot
            foreach ($Segment in @(
                $Segments[0], $Segments[1], $Segments[2],
                [string]$Contract.PlatformTargetId
            )) {
                $ModuleParent = Initialize-SwawHarnessCanonicalModuleDirectory `
                    -Parent $ModuleParent `
                    -Segment $Segment `
                    -Description 'Module identity directory'
            }
            $ReleaseRoot = Join-Path $ModuleParent $Version
            if (Test-SwawHarnessPathExists -Path $ReleaseRoot) {
                $Published.Add((Read-SwawHarnessModuleRelease `
                    -ReleaseRoot $ReleaseRoot `
                    -Contract $Contract `
                    -SourceArtifact $SourceArtifact `
                    -ModulesRoot $ModulesRoot))
                continue
            }

            $StageRoot = Join-Path $ModulesRoot (
                '.publish-' + [Guid]::NewGuid().ToString('N') + '.tmp'
            )
            [void][IO.Directory]::CreateDirectory($StageRoot)
            try {
                $Destination = Join-Path `
                    $StageRoot `
                    ([string]$Contract.ProductBinary)
                [IO.File]::Copy(
                    [string]$SourceArtifact.Path,
                    $Destination,
                    $false
                )
                $Executable = Assert-SwawHarnessRegularFile `
                    -Path $Destination `
                    -Description 'staged Module executable' `
                    -MaximumBytes ([long]$Contract.MaximumBytes)
                $Sha256 = Get-SwawHarnessFileSha256 -Path $Destination
                if ([long]$Executable.Length -ne [long]$SourceArtifact.Length -or
                    $Sha256 -cne [string]$SourceArtifact.Sha256) {
                    throw "Staged Module executable is corrupt: $Destination"
                }
                $Manifest = [ordered]@{
                    schema = $script:SwawHarnessModuleSchema
                    module = [string]$Contract.ModuleId
                    version = $Version
                    platformTargetId = [string]$Contract.PlatformTargetId
                    executable = [ordered]@{
                        name = [string]$Contract.ProductBinary
                        length = [long]$Executable.Length
                        sha256 = $Sha256
                    }
                }
                [IO.File]::WriteAllText(
                    (Join-Path $StageRoot 'swaw-harness.module.json'),
                    (ConvertTo-SwawHarnessJsonText -Value $Manifest),
                    [Text.UTF8Encoding]::new($false)
                )
                [void](Read-SwawHarnessModuleRelease `
                    -ReleaseRoot $StageRoot `
                    -Contract $Contract `
                    -SourceArtifact $SourceArtifact `
                    -ModulesRoot $ModulesRoot)
                Move-SwawHarnessControlledPathWithRetry `
                    -Source $StageRoot `
                    -Destination $ReleaseRoot `
                    -ControlledRoot $ModulesRoot `
                    -Activity 'publishing an immutable Module Release'
                $Published.Add((Read-SwawHarnessModuleRelease `
                    -ReleaseRoot $ReleaseRoot `
                    -Contract $Contract `
                    -SourceArtifact $SourceArtifact `
                    -ModulesRoot $ModulesRoot))
                Write-Host (
                    "[MODULE] $($Contract.ModuleId) $Version " +
                    $Contract.PlatformTargetId
                ) -ForegroundColor Green
            } finally {
                if (Test-SwawHarnessPathExists -Path $StageRoot) {
                    Remove-SwawHarnessControlledPathWithRetry `
                        -Path $StageRoot `
                        -ControlledRoot $ModulesRoot `
                        -Activity 'cleaning Module publication work'
                }
            }
        }
        return $Published.ToArray()
    } finally {
        $Lock.Dispose()
    }
}
