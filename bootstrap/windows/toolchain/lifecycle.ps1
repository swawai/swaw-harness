Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'install-store.ps1')
. (Join-Path $PSScriptRoot 'locator.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot 'rust\install.ps1')
. (Join-Path $PSScriptRoot 'msvc\install.ps1')

$script:SwawHarnessToolchainRecipeVersion = '3'

function Get-SwawHarnessToolchainId {
    param([Parameter(Mandatory = $true)][object]$Contract)

    return Get-SwawHarnessTextSha256 -Value ([string]::Join("`n", @(
        'swaw.harness.bootstrap.toolchain/v4'
        "recipe=$script:SwawHarnessToolchainRecipeVersion"
        "target=$($Contract.PlatformTargetId)"
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
    Assert-SwawHarnessToolchainInstallPathBudget `
        -Context $Context `
        -Contract $Contract `
        -ToolchainId $ToolchainId
    $Selection = Get-SwawHarnessToolchainTargetSelection `
        -Context $Context `
        -ToolchainId $ToolchainId
    return [string]$Selection.Path
}

function Get-SwawHarnessToolchainLayout {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object]$Metadata
    )

    return [pscustomobject][ordered]@{
        Root = Get-SwawHarnessFullPath -Path $Root
        Metadata = $Metadata
        RustRoot = Join-Path $Root 'r'
        MsvcRoot = Join-Path $Root 'm'
    }
}

function Initialize-SwawHarnessToolchainWorkRoot {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Locator
    )

    $WorkRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.StageRoot $Locator) `
        -Root $Context.StageRoot `
        -Activity 'using Bootstrap toolchain work data'
    [void][IO.Directory]::CreateDirectory($WorkRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $WorkRoot `
        -Description 'Bootstrap toolchain work root')
    foreach ($Item in Get-ChildItem -LiteralPath $WorkRoot -Force) {
        if ([string]$Item.Name -cnotin @('publish', 'msi')) {
            throw "Unknown Bootstrap toolchain work entry: $($Item.FullName)"
        }
        Remove-SwawHarnessControlledPathWithRetry `
            -Path ([string]$Item.FullName) `
            -ControlledRoot $Context.StageRoot `
            -Activity 'cleaning interrupted Bootstrap toolchain work'
    }
    return $WorkRoot
}

function Get-SwawHarnessValidToolchain {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string]$ControlledRoot = ''
    )

    try {
        if ([string]::IsNullOrWhiteSpace($ControlledRoot)) {
            $ControlledRoot = [string]$Context.ToolchainRoot
        }
        $InstallRoot = Assert-SwawHarnessPathInsideRoot `
            -Path $InstallRoot `
            -Root $ControlledRoot `
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
            'r' = 'directory'
            'm' = 'directory'
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
            -Expected @('schema', 'toolchainId', 'platformTargetId', 'rust', 'msvc') `
            -Description 'Bootstrap toolchain metadata'
        if ([string]$Metadata.schema -cne
                'swaw.harness.bootstrap.toolchain/v4' -or
            [string]$Metadata.toolchainId -cne
                (Get-SwawHarnessToolchainId -Contract $Contract) -or
            [string]$Metadata.platformTargetId -cne [string]$Contract.PlatformTargetId) {
            return $null
        }
        $RustRoot = Join-Path $InstallRoot 'r'
        $MsvcRoot = Join-Path $InstallRoot 'm'
        if (-not (Test-SwawHarnessRustInstallRecord `
            -Record $Metadata.rust `
            -Contract $Contract `
            -RustRoot $RustRoot `
            -ControlledRoot $ControlledRoot
        ) -or -not (Test-SwawHarnessMsvcInstallRecord `
            -Record $Metadata.msvc `
            -Contract $Contract `
            -MsvcRoot $MsvcRoot `
            -ControlledRoot $ControlledRoot
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
            -ControlledRoot $Context.ToolchainRoot `
            -Full `
            -Detailed)
        [void](Test-SwawHarnessMsvcInstallRecord `
            -Record $Toolchain.Metadata.msvc `
            -Contract $Contract `
            -MsvcRoot $Toolchain.MsvcRoot `
            -ControlledRoot $Context.ToolchainRoot `
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

function Get-SwawHarnessBootstrapToolchain {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract
    )

    $ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
    Assert-SwawHarnessToolchainInstallPathBudget `
        -Context $Context `
        -Contract $Contract `
        -ToolchainId $ToolchainId
    while ($true) {
        $Selection = Get-SwawHarnessToolchainTargetSelection `
            -Context $Context `
            -ToolchainId $ToolchainId
        $TargetPath = [string]$Selection.Path
        $Locator = [string]$Selection.Locator
        $Lock = Enter-SwawHarnessFileLock `
            -Path (Join-Path $Context.LockRoot "toolchain-$Locator.lock") `
            -ControlledRoot $Context.RepositoryDataRoot `
            -TimeoutSeconds 1800
        try {
            $ExistingId = Get-SwawHarnessToolchainLocatorIdentity `
                -Path $TargetPath `
                -Context $Context
            if ($null -ne $ExistingId -and $ExistingId -cne $ToolchainId) {
                continue
            }
            $Ready = Get-SwawHarnessValidToolchain `
                -Context $Context `
                -Contract $Contract `
                -InstallRoot $TargetPath
            if ($null -ne $Ready) {
                [void](Assert-SwawHarnessNativeTreePathBudget `
                    -Root $Ready.Root `
                    -Description 'Installed portable toolchain path')
                return $Ready
            }
            $WorkRoot = Initialize-SwawHarnessToolchainWorkRoot `
                -Context $Context `
                -Locator $Locator
            if ($null -ne $ExistingId) {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path $TargetPath `
                    -ControlledRoot $Context.ToolchainRoot `
                    -Activity 'removing an invalid same-identity toolchain'
            }
            $StagedRoot = Join-Path $WorkRoot 'publish'
            $MsiSourceRoot = Join-Path $WorkRoot 'msi'
            $Validation = [pscustomobject]@{ Value = $null }
            $Validate = {
                param($CandidateRoot)

                $CandidateRoot = [IO.Path]::GetFullPath($CandidateRoot)
                if ($CandidateRoot.Equals(
                        [IO.Path]::GetFullPath($StagedRoot),
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                    $CandidateControlledRoot = $Context.StageRoot
                } elseif ($CandidateRoot.Equals(
                        [IO.Path]::GetFullPath($TargetPath),
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                    $CandidateControlledRoot = $Context.ToolchainRoot
                } else {
                    return $false
                }
                $Candidate = Get-SwawHarnessValidToolchain `
                    -Context $Context `
                    -Contract $Contract `
                    -InstallRoot $CandidateRoot `
                    -ControlledRoot $CandidateControlledRoot
                $Validation.Value = $Candidate
                return ($null -ne $Candidate)
            }
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
                    -StagedToolchainRoot $StagedRoot `
                    -RustInstallRoot $Context.RustupStageRoot
                $Metadata = [ordered]@{
                    schema = 'swaw.harness.bootstrap.toolchain/v4'
                    toolchainId = $ToolchainId
                    platformTargetId = [string]$Contract.PlatformTargetId
                    rust = $RustRecord
                    msvc = $MsvcRecord
                }
                Write-SwawHarnessTextAtomic `
                    -Path (Join-Path $StagedRoot 'toolchain.json') `
                    -Content (ConvertTo-SwawHarnessJsonText -Value $Metadata) `
                    -ControlledRoot $Context.StageRoot
                Publish-SwawHarnessInstallDirectory `
                    -StagedPath $StagedRoot `
                    -TargetPath $TargetPath `
                    -ControlledRoot $Context.RepositoryDataRoot `
                    -Name 'Bootstrap toolchain' `
                    -Validate $Validate
                if ($null -eq $Validation.Value -or
                    -not ([string]$Validation.Value.Root).Equals(
                        $TargetPath,
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                    throw 'Published toolchain validation did not return its target.'
                }
                [void](Assert-SwawHarnessNativeTreePathBudget `
                    -Root $Validation.Value.Root `
                    -Description 'Installed portable toolchain path')
                return $Validation.Value
            } finally {
                Remove-SwawHarnessControlledResidues `
                    -ControlledRoot $Context.StageRoot `
                    -Paths @($WorkRoot) `
                    -Activity 'cleaning staged Bootstrap toolchain data'
            }
        } finally {
            $Lock.Dispose()
        }
    }
}
