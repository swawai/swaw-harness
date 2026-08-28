Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

$script:SwawHarnessToolchainLocatorMinimumLength = 7
$script:SwawHarnessToolchainLocatorMaximumLength = 12

function Get-SwawHarnessToolchainLocatorIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Context
    )

    $Path = Assert-SwawHarnessPathInsideRoot `
        -Path $Path `
        -Root $Context.ToolchainRoot `
        -Activity 'inspecting a Bootstrap toolchain locator'
    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item) {
        return $null
    }
    if (-not $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bootstrap toolchain locator is not a regular directory: $Path"
    }
    $MetadataPath = Join-Path $Path 'toolchain.json'
    try {
        $Metadata = Read-SwawHarnessJsonFile `
            -Path $MetadataPath `
            -Description 'Bootstrap toolchain locator metadata' `
            -MaximumBytes 32MB
    } catch {
        throw (
            "Bootstrap toolchain locator metadata is missing or corrupt at " +
            "'$Path'. Remove that directory after verifying it is not in use. " +
            $_.Exception.Message
        )
    }
    $IdProperty = $Metadata.PSObject.Properties['toolchainId']
    if ($null -eq $IdProperty -or
        [string]$IdProperty.Value -cnotmatch '^[a-f0-9]{64}$') {
        throw "Bootstrap toolchain locator has no valid complete identity: $Path"
    }
    return [string]$IdProperty.Value
}

function Get-SwawHarnessToolchainTargetSelection {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$ToolchainId
    )

    if ($ToolchainId -cnotmatch '^[a-f0-9]{64}$') {
        throw "Invalid complete ToolchainId '$ToolchainId'."
    }
    $ToolchainRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $Context.ToolchainRoot `
        -Root $Context.RepositoryDataRoot `
        -Activity 'using the Bootstrap toolchain store'
    [void][IO.Directory]::CreateDirectory($ToolchainRoot)
    [void](Assert-SwawHarnessControlledRoot `
        -Root $ToolchainRoot `
        -Description 'Bootstrap toolchain store')
    $FirstAvailable = $null
    for (
        $Length = $script:SwawHarnessToolchainLocatorMinimumLength
        $Length -le $script:SwawHarnessToolchainLocatorMaximumLength
        $Length++
    ) {
        $Locator = $ToolchainId.Substring(0, $Length)
        [void](Get-SwawHarnessSafeSegment `
            -Value $Locator `
            -Description 'toolchain locator')
        $Path = Assert-SwawHarnessPathInsideRoot `
            -Path (Join-Path $ToolchainRoot $Locator) `
            -Root $ToolchainRoot `
            -Activity 'selecting a Bootstrap toolchain locator'
        $ExistingId = Get-SwawHarnessToolchainLocatorIdentity `
            -Path $Path `
            -Context $Context
        if ($null -eq $ExistingId) {
            if ($null -eq $FirstAvailable) {
                $FirstAvailable = [pscustomobject][ordered]@{
                    Locator = $Locator
                    Path = $Path
                }
            }
            continue
        }
        if ($ExistingId -ceq $ToolchainId) {
            return [pscustomobject][ordered]@{
                Locator = $Locator
                Path = $Path
            }
        }
    }
    if ($null -ne $FirstAvailable) {
        return $FirstAvailable
    }
    throw (
        'Bootstrap toolchain locator collision exhausted prefixes ' +
        "$($script:SwawHarnessToolchainLocatorMinimumLength) through " +
        "$($script:SwawHarnessToolchainLocatorMaximumLength) for " +
        "$ToolchainId. Remove an unused colliding toolchain or change its " +
        'content identity.'
    )
}
