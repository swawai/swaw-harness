Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\..\builder\filesystem.ps1')
. (Join-Path $PSScriptRoot 'manifest.ps1')
. (Join-Path $PSScriptRoot 'assembly.ps1')
. (Join-Path $PSScriptRoot 'inventory.ps1')

function Get-SwawHarnessMsvcSdkPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Recipe,
        [Parameter(Mandatory = $true)][string]$LeafName
    )

    $Matches = @($Recipe.SdkPayloads | Where-Object {
        [string]$_.LeafName -ieq $LeafName
    })
    if ($Matches.Count -ne 1) {
        throw (
            "Windows SDK manifest must contain one '$LeafName' payload; " +
            "found $($Matches.Count)."
        )
    }
    return $Matches[0]
}

function Install-SwawHarnessMsvcIntoToolchainStage {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$StagedToolchainRoot,
        [Parameter(Mandatory = $true)][string]$MsiSourceRoot
    )

    $MsvcRoot = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $StagedToolchainRoot 'msvc') `
        -Root $Context.BootstrapWindowsRoot `
        -Activity 'staging the MSVC toolchain'
    if (Test-SwawHarnessPathExists -Path $MsvcRoot) {
        throw "MSVC stage must not already exist: $MsvcRoot"
    }
    Write-Host (
        '[LICENSE] Continuing this non-interactive Bootstrap install ' +
        'constitutes acceptance of the Microsoft Build Tools license: ' +
        [string]$Contract.MsvcLicenseUrl
    ) -ForegroundColor Yellow
    $Recipe = Get-SwawHarnessMsvcInstallRecipe `
        -Context $Context `
        -Contract $Contract
    Write-Host (
        "[INFO] MSVC package $($Recipe.ToolPackageVersion), " +
        "SDK $($Recipe.SdkPackageId)"
    ) -ForegroundColor DarkGray

    $MsiSourceRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $MsiSourceRoot `
        -Root $Context.BootstrapWindowsRoot `
        -Activity 'staging Windows SDK installer sources'
    if (Test-SwawHarnessPathExists -Path $MsiSourceRoot) {
        throw "MSVC source stage must not already exist: $MsiSourceRoot"
    }
    $UsedPayloads = [Collections.Generic.List[object]]::new()
    [void][IO.Directory]::CreateDirectory($MsvcRoot)
    try {
        foreach ($Payload in [object[]]$Recipe.ToolPayloads) {
            $Verified = Get-SwawHarnessMsvcVerifiedPayload `
                -Context $Context `
                -Payload $Payload
            $UsedPayloads.Add($Verified)
            Write-Host "[EXT] $($Payload.LeafName)" -ForegroundColor DarkGray
            Expand-SwawHarnessMsvcVsix `
                -ArchivePath ([string]$Verified.Path) `
                -Destination $MsvcRoot `
                -ControlledRoot $Context.BootstrapWindowsRoot
        }

        $MsiPaths = [Collections.Generic.List[string]]::new()
        $CabNames = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )
        $CabCandidates = [string[]]@($Recipe.SdkPayloads |
            Where-Object {
                [IO.Path]::GetExtension([string]$_.LeafName) -ieq '.cab'
            } |
            ForEach-Object { [string]$_.LeafName })
        if ($CabCandidates.Count -eq 0) {
            throw 'Windows SDK package exposes no CAB payloads.'
        }
        foreach ($Payload in [object[]]$Recipe.MsiPayloads) {
            $Verified = Get-SwawHarnessMsvcVerifiedPayload `
                -Context $Context `
                -Payload $Payload
            $UsedPayloads.Add($Verified)
            $MsiPath = Copy-SwawHarnessMsvcPayloadToSourceRoot `
                -Context $Context `
                -Payload $Payload `
                -VerifiedPath ([string]$Verified.Path) `
                -SourceRoot $MsiSourceRoot
            $MsiPaths.Add($MsiPath)
            foreach ($CabName in Get-SwawHarnessMsvcCabNames `
                -MsiPath $MsiPath `
                -CandidateNames $CabCandidates) {
                [void]$CabNames.Add($CabName)
            }
        }
        if ($CabNames.Count -eq 0) {
            throw 'Selected Windows SDK MSIs reference no known CAB payloads.'
        }
        foreach ($CabName in $CabNames) {
            $Payload = Get-SwawHarnessMsvcSdkPayload `
                -Recipe $Recipe `
                -LeafName $CabName
            $Verified = Get-SwawHarnessMsvcVerifiedPayload `
                -Context $Context `
                -Payload $Payload
            $UsedPayloads.Add($Verified)
            [void](Copy-SwawHarnessMsvcPayloadToSourceRoot `
                -Context $Context `
                -Payload $Payload `
                -VerifiedPath ([string]$Verified.Path) `
                -SourceRoot $MsiSourceRoot)
        }

        foreach ($MsiPath in $MsiPaths) {
            Write-Host (
                "[MSI] $([IO.Path]::GetFileName($MsiPath))"
            ) -ForegroundColor DarkGray
            Invoke-SwawHarnessMsvcAdministrativeInstall `
                -Context $Context `
                -MsiPath $MsiPath `
                -Destination $MsvcRoot
        }

        $Versions = Complete-SwawHarnessMsvcAssembly `
            -Context $Context `
            -InstallRoot $MsvcRoot
        $Record = New-SwawHarnessMsvcInstallRecord `
            -Contract $Contract `
            -Recipe $Recipe `
            -Versions $Versions `
            -UsedPayloads ([object[]]$UsedPayloads.ToArray()) `
            -MsvcRoot $MsvcRoot `
            -ControlledRoot $Context.BootstrapWindowsRoot
        if (-not (Test-SwawHarnessMsvcInstallRecord `
            -Record $Record `
            -Contract $Contract `
            -MsvcRoot $MsvcRoot `
            -ControlledRoot $Context.BootstrapWindowsRoot `
            -Detailed
        )) {
            throw 'Staged MSVC installation failed its receipt check.'
        }
        return $Record
    } finally {
        Remove-SwawHarnessControlledResidues `
            -ControlledRoot $Context.BootstrapWindowsRoot `
            -Paths @($MsiSourceRoot) `
            -Activity 'cleaning MSVC installation work data'
    }
}
