Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'install-store.ps1')
. (Join-Path $PSScriptRoot 'rust\install.ps1')
. (Join-Path $PSScriptRoot 'msvc\install.ps1')

$script:SwawHarnessToolchainRecipeVersion = '2'

function Get-SwawHarnessToolchainId {
    param([Parameter(Mandatory = $true)][object]$Contract)

    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        'swaw.harness.bootstrap.toolchain/v2'
        "recipe=$script:SwawHarnessToolchainRecipeVersion"
        "target=$($Contract.TargetId)"
        "rust=$(Get-SwawHarnessRustDefinitionId -Contract $Contract)"
        "msvc=$(Get-SwawHarnessMsvcDefinitionId -Contract $Contract)"
    )))
}

function Get-SwawHarnessToolchainTargetPath {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract
    )

    $ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
    $Locator = "tc-$($ToolchainId.Substring(0, 32))"
    [void](Get-SwawHarnessSafeSegment `
        -Value $Locator `
        -Description 'toolchain id')
    return Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.ToolchainRoot $Locator) `
        -Root $Context.BootstrapWindowsRoot `
        -Activity 'using a Bootstrap toolchain'
}

function Get-SwawHarnessToolchainLayout {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Metadata
    )

    return [pscustomobject][ordered]@{
        Root = Get-SwawHarnessFullPath -Path $Root
        Metadata = $Metadata
        RustRoot = Join-Path $Root 'rust'
        MsvcRoot = Join-Path $Root 'msvc'
    }
}

function Initialize-SwawHarnessToolchainWorkRoot {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$ToolchainId
    )

    $ScopeName = $ToolchainId.Substring(0, 32)
    $WorkRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.WorkRoot $ScopeName) `
        -Root $Context.BootstrapWindowsRoot `
        -Activity 'using Bootstrap toolchain work data'
    [void][IO.Directory]::CreateDirectory($WorkRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $WorkRoot `
        -Description 'Bootstrap toolchain work root')
    foreach ($Item in Get-ChildItem -LiteralPath $WorkRoot -Force) {
        if ([string]$Item.Name -cnotin @('p', 'm')) {
            throw "Unknown Bootstrap toolchain work entry: $($Item.FullName)"
        }
        Remove-SwawHarnessControlledPathWithRetry `
            -Path ([string]$Item.FullName) `
            -ControlledRoot $Context.BootstrapWindowsRoot `
            -Activity 'cleaning interrupted Bootstrap toolchain work'
    }
    return $WorkRoot
}

function Get-SwawHarnessValidToolchain {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$InstallRoot
    )

    try {
        $InstallRoot = Assert-SwawHarnessPathInsideRoot `
            -Path $InstallRoot `
            -Root $Context.BootstrapWindowsRoot `
            -Activity 'validating a Bootstrap toolchain'
        $RootItem = Get-Item `
            -LiteralPath $InstallRoot `
            -Force `
            -ErrorAction SilentlyContinue
        if ($null -eq $RootItem -or -not $RootItem.PSIsContainer -or
            ($RootItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            return $null
        }
        $ExpectedMembers = [ordered]@{
            'rust' = 'directory'
            'msvc' = 'directory'
            'toolchain.json' = 'file'
        }
        $Members = @(Get-ChildItem -LiteralPath $InstallRoot -Force)
        if ($Members.Count -ne $ExpectedMembers.Count) {
            return $null
        }
        foreach ($Member in $Members) {
            $Name = [string]$Member.Name
            if ($ExpectedMembers.Keys -cnotcontains $Name -or
                ($Member.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $null
            }
            $ExpectedKind = [string]$ExpectedMembers[$Name]
            if (($ExpectedKind -ceq 'directory') -ne
                [bool]$Member.PSIsContainer) {
                return $null
            }
        }

        $Metadata = Read-SwawHarnessJsonFile `
            -Path (Join-Path $InstallRoot 'toolchain.json') `
            -Description 'Bootstrap toolchain metadata' `
            -MaximumBytes 32MB
        Assert-SwawHarnessObjectFields `
            -Value $Metadata `
            -Expected @('schema', 'toolchainId', 'targetId', 'rust', 'msvc') `
            -Description 'Bootstrap toolchain metadata'
        if ([string]$Metadata.schema -cne
                'swaw.harness.bootstrap.toolchain/v2' -or
            [string]$Metadata.toolchainId -cne
                (Get-SwawHarnessToolchainId -Contract $Contract) -or
            [string]$Metadata.targetId -cne [string]$Contract.TargetId) {
            return $null
        }
        $RustRoot = Join-Path $InstallRoot 'rust'
        $MsvcRoot = Join-Path $InstallRoot 'msvc'
        if (-not (Test-SwawHarnessRustInstallRecord `
            -Record $Metadata.rust `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $Context.BootstrapWindowsRoot
        ) -or -not (Test-SwawHarnessMsvcInstallRecord `
            -Record $Metadata.msvc `
            -Contract $Contract `
            -MsvcRoot $MsvcRoot `
            -ControlledRoot $Context.BootstrapWindowsRoot
        )) {
            return $null
        }
        return Get-SwawHarnessToolchainLayout `
            -Root $InstallRoot `
            -Metadata $Metadata
    } catch {
        return $null
    }
}

function Test-SwawHarnessToolchainFullInventory {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [switch]$Detailed
    )

    try {
        $Toolchain = Get-SwawHarnessValidToolchain `
            -Context $Context `
            -Contract $Contract `
            -InstallRoot $InstallRoot
        if ($null -eq $Toolchain) {
            throw 'Toolchain failed its fast receipt check.'
        }
        [void](Test-SwawHarnessRustInstallRecord `
            -Record $Toolchain.Metadata.rust `
            -Contract $Contract `
            -RustRoot $Toolchain.RustRoot `
            -ControlledRoot $Context.BootstrapWindowsRoot `
            -Full `
            -Detailed)
        [void](Test-SwawHarnessMsvcInstallRecord `
            -Record $Toolchain.Metadata.msvc `
            -Contract $Contract `
            -MsvcRoot $Toolchain.MsvcRoot `
            -ControlledRoot $Context.BootstrapWindowsRoot `
            -Full `
            -Detailed)
        return $true
    } catch {
        if ($Detailed) {
            throw
        }
        return $false
    }
}

function Assert-SwawHarnessToolchainLocatorNotColliding {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ExpectedToolchainId
    )

    $MetadataPath = Join-Path $TargetPath 'toolchain.json'
    if (-not [IO.File]::Exists($MetadataPath)) {
        return
    }
    try {
        $Metadata = Read-SwawHarnessJsonFile `
            -Path $MetadataPath `
            -Description 'Bootstrap toolchain locator metadata' `
            -MaximumBytes 32MB
    } catch {
        return
    }
    $IdProperty = $Metadata.PSObject.Properties['toolchainId']
    if ($null -ne $IdProperty -and
        [string]$IdProperty.Value -cmatch '^[a-f0-9]{64}$' -and
        [string]$IdProperty.Value -cne $ExpectedToolchainId) {
        throw (
            "Bootstrap toolchain locator collision at '$TargetPath': " +
            "expected $ExpectedToolchainId, found $($IdProperty.Value)."
        )
    }
}

function Get-SwawHarnessBootstrapToolchain {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract
    )

    if ($Context.DataRoot.Length -gt 50) {
        throw (
            'Windows Bootstrap v3 requires a DataRoot path no longer than ' +
            "50 characters: $($Context.DataRoot)"
        )
    }

    $TargetPath = Get-SwawHarnessToolchainTargetPath `
        -Context $Context `
        -Contract $Contract
    [void][IO.Directory]::CreateDirectory($Context.ToolchainRoot)
    $ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
    $Locator = [IO.Path]::GetFileName($TargetPath)
    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot "toolchain-$Locator.lock") `
        -ControlledRoot $Context.BootstrapWindowsRoot `
        -TimeoutSeconds 1800
    try {
        Assert-SwawHarnessToolchainLocatorNotColliding `
            -TargetPath $TargetPath `
            -ExpectedToolchainId $ToolchainId
        $Ready = Get-SwawHarnessValidToolchain `
            -Context $Context `
            -Contract $Contract `
            -InstallRoot $TargetPath
        if ($null -ne $Ready) {
            return $Ready
        }
        $WorkRoot = Initialize-SwawHarnessToolchainWorkRoot `
            -Context $Context `
            -ToolchainId $ToolchainId
        if (Test-SwawHarnessPathExists -Path $TargetPath) {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path $TargetPath `
                -ControlledRoot $Context.BootstrapWindowsRoot `
                -Activity 'removing an invalid content-addressed toolchain'
        }
        $Validation = [pscustomobject]@{ Value = $null }
        $Validate = {
            param($CandidateRoot)

            $Candidate = Get-SwawHarnessValidToolchain `
                -Context $Context `
                -Contract $Contract `
                -InstallRoot $CandidateRoot
            $Validation.Value = $Candidate
            return ($null -ne $Candidate)
        }
        $StagedRoot = Join-Path $WorkRoot 'p'
        $MsiSourceRoot = Join-Path $WorkRoot 'm'
        [void][IO.Directory]::CreateDirectory($StagedRoot)
        try {
            Write-Host '[STEP] Installing portable MSVC...' -ForegroundColor Cyan
            $MsvcRecord = Install-SwawHarnessMsvcIntoToolchainStage `
                -Context $Context `
                -Contract $Contract `
                -StagedToolchainRoot $StagedRoot `
                -MsiSourceRoot $MsiSourceRoot
            $RustRecord = Install-SwawHarnessRustIntoToolchainStage `
                -Context $Context `
                -Contract $Contract `
                -StagedToolchainRoot $StagedRoot
            $Metadata = [ordered]@{
                schema = 'swaw.harness.bootstrap.toolchain/v2'
                toolchainId = $ToolchainId
                targetId = [string]$Contract.TargetId
                rust = $RustRecord
                msvc = $MsvcRecord
            }
            Write-SwawHarnessTextAtomic `
                -Path (Join-Path $StagedRoot 'toolchain.json') `
                -Content (ConvertTo-SwawHarnessJsonText -Value $Metadata) `
                -ControlledRoot $Context.BootstrapWindowsRoot
            Publish-SwawHarnessInstallDirectory `
                -StagedPath $StagedRoot `
                -TargetPath $TargetPath `
                -ControlledRoot $Context.BootstrapWindowsRoot `
                -Name 'Bootstrap toolchain' `
                -Validate $Validate
            if ($null -eq $Validation.Value -or
                -not ([string]$Validation.Value.Root).Equals(
                    $TargetPath,
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                throw 'Published toolchain validation did not return its target.'
            }
            return $Validation.Value
        } finally {
            Remove-SwawHarnessControlledResidues `
                -ControlledRoot $Context.BootstrapWindowsRoot `
                -Paths @($StagedRoot, $MsiSourceRoot) `
                -Activity 'cleaning a staged Bootstrap toolchain'
        }
    } finally {
        $Lock.Dispose()
    }
}
