Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\..\builder\foundation.ps1')
. (Join-Path $PSScriptRoot '..\inventory.ps1')
. (Join-Path $PSScriptRoot 'definition.ps1')

function Get-SwawHarnessRustFileShape {
    param(
        [Parameter(Mandatory = $true)][IO.FileInfo]$Item,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Normalized Rust sysroot contains a reparse point: $RelativePath"
    } elseif ($Item.Length -le 0 -or $Item.Length -gt 4GB) {
        throw "Rust installed file is empty or oversized: $RelativePath"
    }
    return [pscustomobject][ordered]@{
        kind = 'file'
        target = ''
        length = [long]$Item.Length
    }
}

function Get-SwawHarnessRustFileRecords {
    param(
        [Parameter(Mandatory = $true)][string]$RustRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $RustRoot = Get-SwawHarnessFullPath -Path $RustRoot
    $Prefix = $RustRoot.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $Records = [Collections.Generic.List[object]]::new()
    foreach ($Item in Get-SwawHarnessTreeFileItems `
        -Root $RustRoot `
        -ControlledRoot $ControlledRoot `
        -Description 'Rust installation') {
        $FullPath = Get-SwawHarnessFullPath -Path $Item.FullName
        if (-not $FullPath.StartsWith(
            $Prefix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Rust inventory escaped its root: $FullPath"
        }
        $RelativePath = $FullPath.Substring($Prefix.Length)
        [void](Resolve-SwawHarnessChildPath `
            -Root $RustRoot `
            -RelativePath $RelativePath `
            -Description 'Rust inventory file')
        $Shape = Get-SwawHarnessRustFileShape `
            -Item $Item `
            -RelativePath $RelativePath
        $Records.Add([pscustomobject][ordered]@{
            path = $RelativePath
            kind = [string]$Shape.kind
            target = [string]$Shape.target
            length = [long]$Shape.length
            sha256 = Get-SwawHarnessFileSha256 -Path $FullPath
        })
    }
    return Sort-SwawHarnessPathRecords -Records $Records.ToArray()
}

function Get-SwawHarnessRustFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$RustRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $RustRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $RustRoot `
        -Root $ControlledRoot `
        -Activity 'validating a Rust installation'
    [void](Assert-SwawHarnessControlledRoot `
        -Root $RustRoot `
        -Description 'Rust installation root')
    $Path = Resolve-SwawHarnessChildPath `
        -Root $RustRoot `
        -RelativePath $RelativePath `
        -Description 'Rust critical file'
    [void](Assert-SwawHarnessPathInsideRoot `
        -Path (Split-Path -Path $Path -Parent) `
        -Root $ControlledRoot `
        -Activity 'validating a Rust critical file')
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($Item.PSIsContainer) {
        throw "Rust critical file is a directory: $RelativePath"
    }
    $Prefix = $RustRoot.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $FullPath = Get-SwawHarnessFullPath -Path $Item.FullName
    if (-not $FullPath.StartsWith(
        $Prefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Rust critical file escaped its root: $FullPath"
    }
    $ActualRelativePath = $FullPath.Substring($Prefix.Length)
    $Shape = Get-SwawHarnessRustFileShape `
        -Item $Item `
        -RelativePath $ActualRelativePath
    return [pscustomobject][ordered]@{
        path = $ActualRelativePath
        kind = [string]$Shape.kind
        target = [string]$Shape.target
        length = [long]$Shape.length
        sha256 = Get-SwawHarnessFileSha256 -Path $FullPath
    }
}

function New-SwawHarnessRustInstallRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][object]$Probe,
        [Parameter(Mandatory = $true)][string]$RustRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $Files = @(Get-SwawHarnessRustFileRecords `
        -RustRoot $RustRoot `
        -ControlledRoot $ControlledRoot)
    $RequiredPaths = Get-SwawHarnessRustRequiredPaths -Contract $Contract
    $CriticalFiles = @(Select-SwawHarnessRequiredFileRecords `
        -Records $Files `
        -RequiredPaths $RequiredPaths `
        -Description 'Rust installation')
    return [pscustomobject][ordered]@{
        schema = 'swaw.harness.bootstrap.rust-install/v3'
        definitionId = Get-SwawHarnessRustDefinitionId -Contract $Contract
        declaredToolchain = [string]$Contract.RustToolchain
        toolchainName = Get-SwawHarnessRustToolchainName -Contract $Contract
        profile = [string]$Contract.RustProfile
        host = [string]$Contract.PlatformTargetId
        rustupInit = [pscustomobject][ordered]@{
            version = [string]$Contract.RustupInitVersion
            url = [string]$Contract.RustupInitUrl
            length = [long]$Contract.RustupInitLength
            sha256 = [string]$Contract.RustupInitSha256
        }
        probe = $Probe
        inventory = Get-SwawHarnessFileInventorySummary `
            -Records $Files `
            -Description 'Rust installation'
        criticalFiles = $CriticalFiles
    }
}

function Test-SwawHarnessRustInstallRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RustRoot,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [switch]$Full,
        [switch]$Detailed
    )

    try {
        Assert-SwawHarnessObjectFields `
            -Value $Record `
            -Expected @(
                'schema', 'definitionId', 'declaredToolchain',
                'toolchainName', 'profile', 'host', 'rustupInit',
                'probe', 'inventory', 'criticalFiles'
            ) `
            -Description 'Rust install record'
        Assert-SwawHarnessObjectFields `
            -Value $Record.rustupInit `
            -Expected @('version', 'url', 'length', 'sha256') `
            -Description 'Rust installer record'
        Assert-SwawHarnessObjectFields `
            -Value $Record.probe `
            -Expected @(
                'rustupVersion', 'rustcVersion', 'rustcCommit',
                'cargoVersion', 'host'
            ) `
            -Description 'Rust probe record'
        if ([string]$Record.schema -cne
                'swaw.harness.bootstrap.rust-install/v3' -or
            [string]$Record.definitionId -cne
                (Get-SwawHarnessRustDefinitionId -Contract $Contract) -or
            [string]$Record.declaredToolchain -cne
                [string]$Contract.RustToolchain -or
            [string]$Record.toolchainName -cne
                (Get-SwawHarnessRustToolchainName -Contract $Contract) -or
            [string]$Record.profile -cne [string]$Contract.RustProfile -or
            [string]$Record.host -cne [string]$Contract.PlatformTargetId -or
            [string]$Record.rustupInit.version -cne
                [string]$Contract.RustupInitVersion -or
            [string]$Record.rustupInit.url -cne
                [string]$Contract.RustupInitUrl -or
            [long]$Record.rustupInit.length -ne
                [long]$Contract.RustupInitLength -or
            [string]$Record.rustupInit.sha256 -cne
                [string]$Contract.RustupInitSha256 -or
            [string]$Record.probe.rustupVersion -cne
                [string]$Contract.RustupInitVersion -or
            [string]$Record.probe.rustcVersion -cne
                [string]$Contract.RustToolchain -or
            [string]$Record.probe.rustcCommit -cnotmatch '^[a-f0-9]{40}$' -or
            [string]$Record.probe.cargoVersion -cnotmatch '^\d+\.\d+\.\d+' -or
            [string]$Record.probe.host -cne [string]$Contract.PlatformTargetId) {
            throw 'Rust install identity record is inconsistent.'
        }

        Assert-SwawHarnessFileInventorySummary `
            -Summary $Record.inventory `
            -Description 'Rust inventory summary'
        $RequiredPaths = Get-SwawHarnessRustRequiredPaths -Contract $Contract
        $RecordedCriticalFiles = @($Record.criticalFiles)
        if ($RecordedCriticalFiles.Count -ne $RequiredPaths.Count) {
            throw 'Rust critical file record count is invalid.'
        }
        $SelectedCriticalFiles = @(Select-SwawHarnessRequiredFileRecords `
            -Records $RecordedCriticalFiles `
            -RequiredPaths $RequiredPaths `
            -Description 'Rust critical files')
        for ($Index = 0; $Index -lt $RequiredPaths.Count; $Index++) {
            $Actual = Get-SwawHarnessRustFileRecord `
                -RustRoot $RustRoot `
                -ControlledRoot $ControlledRoot `
                -RelativePath $RequiredPaths[$Index]
            if (-not (Test-SwawHarnessFileInventoryRecordEqual `
                -Left $SelectedCriticalFiles[$Index] `
                -Right $Actual)) {
                throw "Rust critical file differs: $($RequiredPaths[$Index])"
            }
        }
        if ($Full) {
            $ActualSummary = Get-SwawHarnessFileInventorySummary `
                -Records @(Get-SwawHarnessRustFileRecords `
                    -RustRoot $RustRoot `
                    -ControlledRoot $ControlledRoot) `
                -Description 'Rust installation'
            if ([long]$ActualSummary.fileCount -ne
                    [long]$Record.inventory.fileCount -or
                [long]$ActualSummary.totalLength -ne
                    [long]$Record.inventory.totalLength -or
                [string]$ActualSummary.sha256 -cne
                    [string]$Record.inventory.sha256) {
                throw 'Rust full inventory summary changed.'
            }
        }
        return $true
    } catch {
        if ($Detailed) {
            throw
        }
        return $false
    }
}
