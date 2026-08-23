Set-StrictMode -Version 2.0

function Get-SwawHarnessFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'A filesystem path cannot be empty.'
    }
    $FullPath = [IO.Path]::GetFullPath($Path)
    $PathRoot = [IO.Path]::GetPathRoot($FullPath)
    if ($FullPath.Length -gt $PathRoot.Length) {
        $FullPath = $FullPath.TrimEnd([char[]]@(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ))
    }
    return $FullPath
}

function Assert-SwawHarnessControlledRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $FullRoot = Get-SwawHarnessFullPath -Path $Root
    $Item = Get-Item -LiteralPath $FullRoot -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item) {
        return $FullRoot
    }
    if (-not $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Description must be a regular directory: $FullRoot"
    }
    return $FullRoot
}

function Assert-SwawHarnessPathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Activity
    )

    $FullRoot = Assert-SwawHarnessControlledRoot `
        -Root $Root `
        -Description 'Controlled root'
    $FullPath = Get-SwawHarnessFullPath -Path $Path
    $Prefix = $FullRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith(
        $Prefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing $Activity outside the controlled root: $FullPath"
    }

    $Relative = $FullPath.Substring($Prefix.Length)
    $Segments = $Relative.Split(
        [char[]]@(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        ),
        [StringSplitOptions]::RemoveEmptyEntries
    )
    $Current = $FullRoot
    for ($Index = 0; $Index -lt $Segments.Length; $Index++) {
        $Current = Join-Path $Current $Segments[$Index]
        $Item = Get-Item -LiteralPath $Current -Force -ErrorAction SilentlyContinue
        if ($null -eq $Item) {
            continue
        }
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing $Activity through a reparse point: $Current"
        }
        if ($Index -lt ($Segments.Length - 1) -and -not $Item.PSIsContainer) {
            throw "Refusing $Activity through a non-directory: $Current"
        }
    }
    return $FullPath
}

function Assert-SwawHarnessRegularFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [long]$MaximumBytes = 536870912
    )

    $FullPath = Get-SwawHarnessFullPath -Path $Path
    $Item = Get-Item -LiteralPath $FullPath -Force -ErrorAction SilentlyContinue
    if ($null -eq $Item -or $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        $Item.Length -le 0 -or $Item.Length -gt $MaximumBytes) {
        throw "$Description must be a bounded regular file: $FullPath"
    }
    return $Item
}

function Get-SwawHarnessSafeSegment {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($Value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        throw "Invalid $Description '$Value'."
    }
    return $Value
}

function Resolve-SwawHarnessChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath)) {
        throw "Invalid $Description '$RelativePath': expected a relative path."
    }
    $FullRoot = Get-SwawHarnessFullPath -Path $Root
    $Prefix = $FullRoot.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $FullPath = Get-SwawHarnessFullPath -Path (
        Join-Path $FullRoot $RelativePath
    )
    if (-not $FullPath.StartsWith(
        $Prefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Invalid $Description '$RelativePath': path escapes its root."
    }
    return $FullPath
}

function Assert-SwawHarnessWindowsX64 {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'Windows Bootstrap can run on Windows only.'
    }
    $Architecture = if (-not [string]::IsNullOrWhiteSpace(
        $env:PROCESSOR_ARCHITEW6432
    )) {
        [string]$env:PROCESSOR_ARCHITEW6432
    } else {
        [string]$env:PROCESSOR_ARCHITECTURE
    }
    if (-not [Environment]::Is64BitOperatingSystem -or
        $Architecture.Trim().ToUpperInvariant() -cne 'AMD64') {
        throw "Windows Bootstrap requires x64 Windows; detected '$Architecture'."
    }
}

function Get-SwawHarnessFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.
        ToLowerInvariant()
}

function Get-SwawHarnessTextSha256 {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return ([BitConverter]::ToString(
            $Algorithm.ComputeHash($Bytes)
        )).Replace('-', '').ToLowerInvariant()
    } finally {
        $Algorithm.Dispose()
    }
}

function ConvertTo-SwawHarnessJsonText {
    param([Parameter(Mandatory = $true)]$Value)

    $Json = $Value | ConvertTo-Json -Depth 12
    $Json = $Json.Replace("`r`n", "`n").
        Replace("`r", "`n").
        Replace("`n", "`r`n")
    return "$Json`r`n"
}

function Read-SwawHarnessJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Description,
        [long]$MaximumBytes = 1048576
    )

    [void](Assert-SwawHarnessRegularFile `
        -Path $Path `
        -Description $Description `
        -MaximumBytes $MaximumBytes)
    try {
        return [IO.File]::ReadAllText(
            (Get-SwawHarnessFullPath -Path $Path),
            [Text.Encoding]::UTF8
        ) | ConvertFrom-Json
    } catch {
        throw "Cannot parse $Description JSON: $($_.Exception.Message)"
    }
}

function Assert-SwawHarnessObjectFields {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Description
    )

    if ($null -eq $Value -or $null -eq $Value.PSObject) {
        throw "$Description must be an object."
    }
    [string[]]$Actual = @($Value.PSObject.Properties.Name)
    foreach ($Name in $Expected) {
        if ($Actual -cnotcontains $Name) {
            throw "$Description is missing '$Name'."
        }
    }
    foreach ($Name in $Actual) {
        if ($Expected -cnotcontains $Name) {
            throw "$Description contains unknown field '$Name'."
        }
    }
}

function Write-SwawHarnessTextAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $Path = Assert-SwawHarnessPathInsideRoot `
        -Path $Path `
        -Root $ControlledRoot `
        -Activity 'writing an atomic file'
    $Parent = Split-Path -Path $Path -Parent
    [void][IO.Directory]::CreateDirectory($Parent)
    $Leaf = [IO.Path]::GetFileName($Path)
    $Token = [Guid]::NewGuid().ToString('N')
    $Stage = Join-Path $Parent ".$Leaf.$Token.tmp"
    $Backup = Join-Path $Parent ".$Leaf.$Token.backup"
    $CommitAttempted = $false
    $Published = $false
    try {
        [IO.File]::WriteAllText(
            $Stage,
            $Content,
            [Text.UTF8Encoding]::new($false)
        )
        $CommitAttempted = $true
        if ([IO.File]::Exists($Path)) {
            $Existing = Get-Item `
                -LiteralPath $Path `
                -Force `
                -ErrorAction Stop
            if ($Existing.PSIsContainer -or
                ($Existing.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Atomic destination is not a regular file: $Path"
            }
            [IO.File]::Replace($Stage, $Path, $Backup, $true)
        } else {
            $Existing = Get-Item `
                -LiteralPath $Path `
                -Force `
                -ErrorAction SilentlyContinue
            if ($null -ne $Existing) {
                throw "Atomic destination is not a regular file: $Path"
            }
            [IO.File]::Move($Stage, $Path)
        }
        $Published = $true
    } catch {
        if ($CommitAttempted) {
            throw (
                "Atomic publication failed for '$Path'. Recovery files " +
                "were preserved when present: '$Stage', '$Backup'. " +
                $_.Exception.Message
            )
        }
        throw
    } finally {
        $Cleanup = if ($Published) {
            @($Stage, $Backup)
        } elseif (-not $CommitAttempted) {
            @($Stage)
        } else {
            @()
        }
        foreach ($Residue in $Cleanup) {
            if ([IO.File]::Exists($Residue)) {
                try {
                    [IO.File]::Delete($Residue)
                } catch {
                    Write-Warning "Temporary file could not be removed: $Residue"
                }
            }
        }
    }
}

function Enter-SwawHarnessFileLock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [int]$TimeoutSeconds = 120
    )

    $Path = Assert-SwawHarnessPathInsideRoot `
        -Path $Path `
        -Root $ControlledRoot `
        -Activity 'opening a lock file'
    [void][IO.Directory]::CreateDirectory((Split-Path -Path $Path -Parent))
    $Deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            return [IO.FileStream]::new(
                $Path,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        } catch [IO.IOException] {
            if ([DateTime]::UtcNow -ge $Deadline) {
                throw "Timed out waiting for lock: $Path"
            }
            Start-Sleep -Milliseconds 100
        }
    } while ($true)
}
