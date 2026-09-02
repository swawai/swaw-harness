Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')
. (Join-Path $PSScriptRoot 'physical-path.ps1')

$script:SwawHarnessMaximumRepositoryRootLength = 60
$script:SwawHarnessMaximumNativePathLength = 240
$script:SwawHarnessMaximumUserIdLength = 16
$script:SwawHarnessPinnedRustLibraryFileLength = 51
$script:SwawHarnessPinnedMsvcRelativePathLength = 121
$script:SwawHarnessPinnedMsvcInstalledRelativePath = (
    'Windows Kits\10\Include\10.0.28000.0\cppwinrt\winrt\impl\' +
    'windows.applicationmodel.appointments.appointmentsprovider.0.h'
)

function Test-SwawHarnessFullyQualifiedPath {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        if (-not [IO.Path]::IsPathRooted($Path)) {
            return $false
        }
        $Root = [IO.Path]::GetPathRoot($Path)
    } catch [ArgumentException] {
        return $false
    }
    return $Root -cmatch '^[A-Za-z]:[\\/]' -or $Root.StartsWith('\\')
}

function Get-SwawHarnessWindowsPathBudget {
    return [pscustomobject][ordered]@{
        MaximumRepositoryRootLength =
            $script:SwawHarnessMaximumRepositoryRootLength
        MaximumNativePathLength = $script:SwawHarnessMaximumNativePathLength
        MaximumUserIdLength = $script:SwawHarnessMaximumUserIdLength
    }
}

function Assert-SwawHarnessRepositoryRootPathBudget {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $RepositoryRoot = Assert-SwawHarnessPhysicalRepositoryRoot `
        -RepositoryRoot $RepositoryRoot
    if ($RepositoryRoot.Length -gt
        $script:SwawHarnessMaximumRepositoryRootLength) {
        throw (
            'Windows Bootstrap supports an absolute repository root no longer ' +
            "than $($script:SwawHarnessMaximumRepositoryRootLength) " +
            "characters; measured $($RepositoryRoot.Length): $RepositoryRoot. " +
            'Move the repository to a shorter parent path before Bootstrap.'
        )
    }
    return $RepositoryRoot
}

function Assert-SwawHarnessNativePathBudget {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Longest = $null
    foreach ($Path in $Paths) {
        $FullPath = Get-SwawHarnessFullPath -Path $Path
        if ($null -eq $Longest -or
            $FullPath.Length -gt ([string]$Longest).Length) {
            $Longest = $FullPath
        }
        if ($FullPath.Length -gt
            $script:SwawHarnessMaximumNativePathLength) {
            throw (
                "$Description exceeds the Windows Bootstrap native-path " +
                "budget of $($script:SwawHarnessMaximumNativePathLength) " +
                "characters; measured $($FullPath.Length): $FullPath. " +
                'Use a HarnessRoot within the declared 60-character ' +
                'support boundary.'
            )
        }
    }
    return $Longest
}

function Assert-SwawHarnessNativeTreePathBudget {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Root = Get-SwawHarnessFullPath -Path $Root
    $Paths = [Collections.Generic.List[string]]::new()
    $Paths.Add($Root)
    if ([IO.Directory]::Exists($Root)) {
        foreach ($Item in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
            $Paths.Add([string]$Item.FullName)
        }
    }
    return Assert-SwawHarnessNativePathBudget `
        -Paths $Paths.ToArray() `
        -Description $Description
}

function Assert-SwawHarnessToolchainInstallPathBudget {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$ToolchainId
    )

    $MaximumLocator = $ToolchainId.Substring(
        0,
        $script:SwawHarnessToolchainLocatorMaximumLength
    )
    $ToolchainName = Get-SwawHarnessRustToolchainName -Contract $Contract
    $LongestPinnedRustLibrary = 'x' *
        $script:SwawHarnessPinnedRustLibraryFileLength
    $RustLibrarySuffix = Join-Path (
        "lib\rustlib\$($Contract.PlatformTargetId)\lib"
    ) $LongestPinnedRustLibrary
    $Paths = [string[]]@(
        (Join-Path (
            Join-Path $Context.RustupStageRoot (
                "r\toolchains\$ToolchainName"
            )
        ) $RustLibrarySuffix)
        (Join-Path (
            Join-Path $Context.ToolchainRoot "$MaximumLocator\r"
        ) $RustLibrarySuffix)
        (Join-Path (
            Join-Path $Context.StageRoot "$MaximumLocator\publish"
        ) ('x' * $script:SwawHarnessPinnedMsvcRelativePathLength))
        (Join-Path $Context.StageRoot "$MaximumLocator\msi")
        (Join-Path (
            Join-Path $Context.HarnessRoot (
                "data\$('u' * $script:SwawHarnessMaximumUserIdLength)\" +
                "release\dev\setup\$MaximumLocator\m"
            )
        ) $script:SwawHarnessPinnedMsvcInstalledRelativePath)
    )
    [void](Assert-SwawHarnessNativePathBudget `
        -Paths $Paths `
        -Description 'Planned portable toolchain path')
}

function Get-SwawHarnessCargoPlannedPaths {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId,
        [Parameter(Mandatory = $true)][string]$Package,
        [Parameter(Mandatory = $true)][string]$Binary
    )

    $ProfileRoot = Join-Path $TargetRoot "$PlatformTargetId\release"
    $FingerprintRoot = Join-Path $ProfileRoot (
        ".fingerprint\$Package-$('0' * 16)"
    )
    $CrateName = $Package.Replace('-', '_')
    return [string[]]@(
        (Join-Path $ProfileRoot $Binary)
        (Join-Path $FingerprintRoot "lib-$CrateName.json")
        (Join-Path $FingerprintRoot "bin-$Package.json")
        (Join-Path $FingerprintRoot "dep-lib-$CrateName")
        (Join-Path $FingerprintRoot "dep-bin-$Package")
        (Join-Path $ProfileRoot "deps\$CrateName-$('0' * 16).exe")
        (Join-Path $ProfileRoot "deps\$CrateName-$('0' * 16).pdb")
    )
}

function Assert-SwawHarnessCargoBuildPathBudget {
    param(
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$CargoPath,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $Paths = [Collections.Generic.List[string]]::new()
    foreach ($Path in Get-SwawHarnessCargoPlannedPaths `
        -TargetRoot $TargetRoot `
        -PlatformTargetId ([string]$Contract.PlatformTargetId) `
        -Package ([string]$Contract.ProductPackage) `
        -Binary ([string]$Contract.BuildBinary)) {
        $Paths.Add($Path)
    }
    foreach ($Path in @($CargoPath, $ManifestPath, $WorkingDirectory)) {
        $Paths.Add([string]$Path)
    }
    [void](Assert-SwawHarnessNativePathBudget `
        -Paths $Paths.ToArray() `
        -Description 'Planned Cargo build path')
}

function Assert-SwawHarnessExternalProcessPathBudget {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Collections.IDictionary]$EnvironmentVariables = @{}
    )

    $Paths = [Collections.Generic.List[string]]::new()
    $Paths.Add($Executable)
    $Paths.Add($WorkingDirectory)
    foreach ($Argument in $Arguments) {
        $Value = [string]$Argument
        $EmbeddedPathChecked = $false
        foreach ($Prefix in @('/Fo', '/Fd', '/Fe', '/out:', 'TARGETDIR=')) {
            if ($Value.StartsWith(
                $Prefix,
                [StringComparison]::OrdinalIgnoreCase
            )) {
                $EmbeddedPathChecked = $true
                $Candidate = $Value.Substring($Prefix.Length)
                if (Test-SwawHarnessFullyQualifiedPath -Path $Candidate) {
                    $Paths.Add($Candidate)
                }
                break
            }
        }
        if (-not $EmbeddedPathChecked -and
            (Test-SwawHarnessFullyQualifiedPath -Path $Value)) {
            $Paths.Add($Value)
        }
    }
    foreach ($Name in $EnvironmentVariables.Keys) {
        if ([string]$Name -ieq 'Path') {
            continue
        }
        foreach ($Value in ([string]$EnvironmentVariables[$Name]).Split(';')) {
            if (Test-SwawHarnessFullyQualifiedPath -Path $Value) {
                $Paths.Add($Value)
            }
        }
    }
    [void](Assert-SwawHarnessNativePathBudget `
        -Paths $Paths.ToArray() `
        -Description 'External tool process path')
}
