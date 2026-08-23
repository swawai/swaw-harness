Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')

function Test-SwawHarnessPathExists {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [IO.Directory]::Exists($Path) -or [IO.File]::Exists($Path)
}

function Remove-SwawHarnessTreeEntry {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item) {
        return
    }
    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($Item.PSIsContainer) {
            [IO.Directory]::Delete($Item.FullName, $false)
        } else {
            [IO.File]::Delete($Item.FullName)
        }
        return
    }
    if ($Item.PSIsContainer) {
        foreach ($Child in [IO.Directory]::EnumerateFileSystemEntries(
            $Item.FullName
        )) {
            Remove-SwawHarnessTreeEntry -Path $Child
        }
        [IO.Directory]::Delete($Item.FullName, $false)
        return
    }
    if (($Item.Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0) {
        $Item.Attributes = $Item.Attributes -band `
            (-bnot [IO.FileAttributes]::ReadOnly)
    }
    [IO.File]::Delete($Item.FullName)
}

function Remove-SwawHarnessControlledPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    $Path = Assert-SwawHarnessPathInsideRoot `
        -Path $Path `
        -Root $ControlledRoot `
        -Activity $Activity
    Remove-SwawHarnessTreeEntry -Path $Path
}

function Remove-SwawHarnessControlledPathWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$Activity,
        [int]$Attempts = 5
    )

    $LastError = $null
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        if (-not (Test-SwawHarnessPathExists -Path $Path)) {
            return
        }
        try {
            Remove-SwawHarnessControlledPath `
                -Path $Path `
                -ControlledRoot $ControlledRoot `
                -Activity $Activity
            if (-not (Test-SwawHarnessPathExists -Path $Path)) {
                return
            }
        } catch {
            $LastError = $_
        }
        if ($Attempt -lt $Attempts) {
            Start-Sleep -Milliseconds (150 * $Attempt)
        }
    }
    $Detail = if ($null -eq $LastError) {
        'the path still exists'
    } else {
        $LastError.Exception.Message
    }
    throw (
        "Cannot finish $Activity after $Attempts attempts: $Path. " +
        'Release processes that lock the path, then retry Bootstrap. ' +
        "Last error: $Detail"
    )
}

function Remove-SwawHarnessControlledResidues {
    param(
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Paths,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    foreach ($Path in $Paths) {
        if (-not (Test-SwawHarnessPathExists -Path $Path)) {
            continue
        }
        try {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path $Path `
                -ControlledRoot $ControlledRoot `
                -Activity $Activity
        } catch {
            Write-Warning $_.Exception.Message
        }
    }
}

function Move-SwawHarnessControlledPathWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$Activity,
        [int]$Attempts = 5
    )

    $Source = Assert-SwawHarnessPathInsideRoot `
        -Path $Source `
        -Root $ControlledRoot `
        -Activity $Activity
    $Destination = Assert-SwawHarnessPathInsideRoot `
        -Path $Destination `
        -Root $ControlledRoot `
        -Activity $Activity
    [void][IO.Directory]::CreateDirectory(
        (Split-Path -Path $Destination -Parent)
    )
    $LastError = $null
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        if (-not (Test-SwawHarnessPathExists -Path $Source)) {
            throw "Cannot $Activity because the source is missing: $Source"
        }
        if (Test-SwawHarnessPathExists -Path $Destination) {
            throw "Cannot $Activity because the destination exists: $Destination"
        }
        try {
            if ([IO.Directory]::Exists($Source)) {
                [IO.Directory]::Move($Source, $Destination)
            } elseif ([IO.File]::Exists($Source)) {
                [IO.File]::Move($Source, $Destination)
            } else {
                throw "Cannot $Activity because the source is missing: $Source"
            }
            return
        } catch {
            $LastError = $_
        }
        if ($Attempt -lt $Attempts) {
            Start-Sleep -Milliseconds (150 * $Attempt)
        }
    }
    throw (
        "Cannot finish $Activity after $Attempts attempts. " +
        "Release processes that lock '$Source', then retry Bootstrap. " +
        "Last error: $($LastError.Exception.Message)"
    )
}
