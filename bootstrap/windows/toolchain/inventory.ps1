Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Get-SwawHarnessTreeFileItemsInternal {
    param([Parameter(Mandatory = $true)][string]$Root)

    foreach ($Path in [IO.Directory]::EnumerateFileSystemEntries($Root)) {
        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        $IsReparse = ($Item.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0
        if ($Item.PSIsContainer) {
            if ($IsReparse) {
                throw "Inventory cannot traverse a directory reparse point: $Path"
            }
            Get-SwawHarnessTreeFileItemsInternal -Root $Item.FullName
        } else {
            Write-Output $Item
        }
    }
}

function Get-SwawHarnessTreeFileItems {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $Root = Assert-SwawHarnessPathInsideRoot `
        -Path $Root `
        -Root $ControlledRoot `
        -Activity "inventorying $Description"
    $Item = Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item -or -not $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description root must be a regular directory: $Root"
    }
    Get-SwawHarnessTreeFileItemsInternal -Root $Root
}

function Sort-SwawHarnessPathRecords {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Records
    )

    $Sorted = [object[]]@($Records)
    if ($Sorted.Count -gt 1) {
        # Windows paths compare case-insensitively; the ordinal tie-breaker
        # keeps inventory hashes stable across PowerShell/.NET runtimes.
        $Comparison = [Comparison[object]]{
            param($Left, $Right)

            $Result = [StringComparer]::OrdinalIgnoreCase.Compare(
                [string]$Left.path,
                [string]$Right.path
            )
            if ($Result -eq 0) {
                $Result = [StringComparer]::Ordinal.Compare(
                    [string]$Left.path,
                    [string]$Right.path
                )
            }
            return $Result
        }
        [Array]::Sort($Sorted, $Comparison)
    }
    return $Sorted
}

function Assert-SwawHarnessFileInventoryRecord {
    param(
        [Parameter(Mandatory = $true)][object]$Record,
        [Parameter(Mandatory = $true)][string]$Description
    )

    Assert-SwawHarnessObjectFields `
        -Value $Record `
        -Expected @('path', 'kind', 'target', 'length', 'sha256') `
        -Description $Description
    $Path = [string]$Record.path
    $Kind = [string]$Record.kind
    $Target = [string]$Record.target
    $Length = [long]$Record.length
    $Sha256 = [string]$Record.sha256
    if ([string]::IsNullOrWhiteSpace($Path) -or
        $Kind -cnotin @('file', 'symlink') -or
        $Length -lt 0 -or $Length -gt 4GB -or
        $Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        ($Kind -ceq 'file' -and
            -not [string]::IsNullOrEmpty($Target)) -or
        ($Kind -ceq 'symlink' -and
            [string]::IsNullOrWhiteSpace($Target))) {
        throw "$Description is invalid."
    }
}

function Add-SwawHarnessInventoryDigestValue {
    param(
        [Parameter(Mandatory = $true)][Text.StringBuilder]$Builder,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )

    $Length = [Text.Encoding]::UTF8.GetByteCount($Value).ToString(
        [Globalization.CultureInfo]::InvariantCulture
    )
    [void]$Builder.Append($Name)
    [void]$Builder.Append('=')
    [void]$Builder.Append($Length)
    [void]$Builder.Append(':')
    [void]$Builder.Append($Value)
    [void]$Builder.Append("`n")
}

function Get-SwawHarnessFileInventorySummary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Records,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($Records.Count -eq 0 -or $Records.Count -gt 200000) {
        throw "$Description file count is invalid."
    }
    $Sorted = @(Sort-SwawHarnessPathRecords -Records $Records)
    $Seen = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $Builder = [Text.StringBuilder]::new()
    [void]$Builder.Append("swaw.harness.bootstrap.file-inventory/v1`n")
    [long]$TotalLength = 0
    foreach ($Record in $Sorted) {
        Assert-SwawHarnessFileInventoryRecord `
            -Record $Record `
            -Description "$Description file record"
        if (-not $Seen.Add([string]$Record.path)) {
            throw "$Description contains a duplicate path: $($Record.path)"
        }
        $TotalLength += [long]$Record.length
        Add-SwawHarnessInventoryDigestValue `
            -Builder $Builder -Name 'path' -Value ([string]$Record.path)
        Add-SwawHarnessInventoryDigestValue `
            -Builder $Builder -Name 'kind' -Value ([string]$Record.kind)
        Add-SwawHarnessInventoryDigestValue `
            -Builder $Builder -Name 'target' -Value ([string]$Record.target)
        Add-SwawHarnessInventoryDigestValue `
            -Builder $Builder -Name 'length' -Value (
                ([long]$Record.length).ToString(
                    [Globalization.CultureInfo]::InvariantCulture
                )
            )
        Add-SwawHarnessInventoryDigestValue `
            -Builder $Builder -Name 'sha256' -Value ([string]$Record.sha256)
    }
    return [pscustomobject][ordered]@{
        schema = 'swaw.harness.bootstrap.file-inventory/v1'
        fileCount = [long]$Sorted.Count
        totalLength = $TotalLength
        sha256 = Get-SwawHarnessTextSha256 -Value $Builder.ToString()
    }
}

function Assert-SwawHarnessFileInventorySummary {
    param(
        [Parameter(Mandatory = $true)][object]$Summary,
        [Parameter(Mandatory = $true)][string]$Description
    )

    Assert-SwawHarnessObjectFields `
        -Value $Summary `
        -Expected @('schema', 'fileCount', 'totalLength', 'sha256') `
        -Description $Description
    if ([string]$Summary.schema -cne
            'swaw.harness.bootstrap.file-inventory/v1' -or
        [long]$Summary.fileCount -le 0 -or
        [long]$Summary.fileCount -gt 200000 -or
        [long]$Summary.totalLength -le 0 -or
        [string]$Summary.sha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw "$Description is invalid."
    }
}
function Select-SwawHarnessRequiredFileRecords {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string[]]$RequiredPaths,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $ByPath = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($Record in $Records) {
        Assert-SwawHarnessFileInventoryRecord `
            -Record $Record `
            -Description "$Description file record"
        if ($ByPath.ContainsKey([string]$Record.path)) {
            throw "$Description contains a duplicate path: $($Record.path)"
        }
        $ByPath.Add([string]$Record.path, $Record)
    }
    $Selected = [Collections.Generic.List[object]]::new()
    foreach ($RequiredPath in $RequiredPaths) {
        $Record = $null
        if (-not $ByPath.TryGetValue($RequiredPath, [ref]$Record)) {
            throw "$Description required file is missing: $RequiredPath"
        }
        $Selected.Add($Record)
    }
    return [object[]]$Selected.ToArray()
}

function Test-SwawHarnessFileInventoryRecordEqual {
    param(
        [Parameter(Mandatory = $true)][object]$Left,
        [Parameter(Mandatory = $true)][object]$Right
    )

    return (
        ([string]$Left.path).Equals(
            [string]$Right.path,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [string]$Left.kind -ceq [string]$Right.kind -and
        [string]$Left.target -ceq [string]$Right.target -and
        [long]$Left.length -eq [long]$Right.length -and
        [string]$Left.sha256 -ceq [string]$Right.sha256
    )
}
