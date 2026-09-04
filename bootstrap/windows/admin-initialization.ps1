Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'builder\foundation.ps1')
. (Join-Path $PSScriptRoot 'builder\filesystem.ps1')
. (Join-Path $PSScriptRoot 'host\contract.ps1')
. (Join-Path $PSScriptRoot 'user\contract.ps1')

function Assert-SwawHarnessAdminInitializationDirectory {
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

function Read-SwawHarnessCoreHostVersionPointer {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Pointer = Assert-SwawHarnessRegularFile `
        -Path $Path `
        -Description 'Core Host version pointer' `
        -MaximumBytes 128
    [byte[]]$Bytes = [IO.File]::ReadAllBytes([string]$Pointer.FullName)
    if ($Bytes.Count -lt 6 -or $Bytes[$Bytes.Count - 1] -ne 10 -or
        @($Bytes | Where-Object { $_ -gt 127 }).Count -ne 0) {
        throw "Core Host version pointer has invalid framing: $Path"
    }
    $ContentLength = $Bytes.Count - 1
    if ($ContentLength -gt 0 -and $Bytes[$ContentLength - 1] -eq 13) {
        $ContentLength--
    }
    $Version = [Text.Encoding]::ASCII.GetString($Bytes, 0, $ContentLength)
    if ($Version -cnotmatch
        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
        throw "Core Host version pointer is not an exact version: $Path"
    }
    return $Version
}

function Publish-SwawHarnessAdminCoreHostVersionPointer {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$HostModuleRelease
    )

    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $PSScriptRoot 'contract.json')
    $Contract = Read-SwawHarnessWindowsCoreHostContract `
        -Path (Join-Path $PSScriptRoot 'host\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    if ([string]$HostModuleRelease.ModuleId -cne $Contract.ModuleId -or
        [string]$HostModuleRelease.Version -cne $Contract.ModuleVersion -or
        [string]$HostModuleRelease.PlatformTargetId -cne
            $Contract.PlatformTargetId) {
        throw 'Core Host Module Release does not match its build contract.'
    }

    $DataHome = Assert-SwawHarnessAdminInitializationDirectory `
        -Path (Join-Path $Context.HarnessRoot 'data') `
        -Description 'DataHome'
    $AdminRoot = Assert-SwawHarnessAdminInitializationDirectory `
        -Path (Join-Path $DataHome 'admin') `
        -Description 'Admin UserHome'
    $HostRoot = Join-Path $AdminRoot 'host'
    [void][IO.Directory]::CreateDirectory($HostRoot)
    $HostRoot = Assert-SwawHarnessAdminInitializationDirectory `
        -Path $HostRoot `
        -Description 'Admin Core Host selection root'
    $PointerPath = Join-Path `
        $HostRoot `
        "current.$($Contract.PlatformTargetId)"
    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $HostRoot (
            ".select-$($Contract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $HostRoot `
        -TimeoutSeconds 1800
    try {
        $Matches = $false
        try {
            $Matches = (Read-SwawHarnessCoreHostVersionPointer `
                -Path $PointerPath) -ceq $Contract.ModuleVersion
        } catch {}
        if (-not $Matches) {
            Write-SwawHarnessTextAtomic `
                -Path $PointerPath `
                -Content "$($Contract.ModuleVersion)`n" `
                -ControlledRoot $HostRoot
        }
        if ((Read-SwawHarnessCoreHostVersionPointer `
            -Path $PointerPath) -cne $Contract.ModuleVersion) {
            throw 'Core Host version pointer publication failed.'
        }
        return $PointerPath
    } finally {
        $Lock.Dispose()
    }
}

function Publish-SwawHarnessAdminUserCli {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$BootstrapRelease
    )

    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $PSScriptRoot 'contract.json')
    $Contract = Read-SwawHarnessWindowsUserCliContract `
        -Path (Join-Path $PSScriptRoot 'user\contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $Sources = @($BootstrapRelease.Artifacts | Where-Object {
        [string]$_.Name -ceq [string]$Contract.ProductBinary
    })
    if ($Sources.Count -ne 1) {
        throw 'Bootstrap Release must contain exactly one User CLI executable.'
    }
    $Source = $Sources[0]
    $DataHome = Assert-SwawHarnessAdminInitializationDirectory `
        -Path (Join-Path $Context.HarnessRoot 'data') `
        -Description 'DataHome'
    $Destination = Join-Path $DataHome 'admin.exe'
    $Existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($null -ne $Existing -and
        -not $Existing.PSIsContainer -and
        ($Existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
        [long]$Existing.Length -eq [long]$Source.Length -and
        (Get-SwawHarnessFileSha256 -Path $Destination) -ceq
            [string]$Source.Sha256) {
        return $Destination
    }
    $Stage = Join-Path $DataHome (
        '.admin-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    )
    $Backup = "$Stage.backup"
    try {
        [IO.File]::Copy([string]$Source.Path, $Stage, $false)
        $Staged = Assert-SwawHarnessRegularFile `
            -Path $Stage `
            -Description 'staged Admin User CLI executable' `
            -MaximumBytes $Contract.MaximumBytes
        if ([long]$Staged.Length -ne [long]$Source.Length -or
            (Get-SwawHarnessFileSha256 -Path $Stage) -cne
                [string]$Source.Sha256) {
            throw 'Staged Admin User CLI executable is corrupt.'
        }
        $DestinationItem = Get-Item `
            -LiteralPath $Destination `
            -Force `
            -ErrorAction SilentlyContinue
        if ($null -eq $DestinationItem) {
            try {
                [IO.File]::Move($Stage, $Destination)
            } catch {
                $Concurrent = Get-Item `
                    -LiteralPath $Destination `
                    -Force `
                    -ErrorAction SilentlyContinue
                if ($null -eq $Concurrent -or $Concurrent.PSIsContainer -or
                    ($Concurrent.Attributes -band
                        [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    [long]$Concurrent.Length -ne [long]$Source.Length -or
                    (Get-SwawHarnessFileSha256 -Path $Destination) -cne
                        [string]$Source.Sha256) {
                    throw
                }
            }
        } elseif ($DestinationItem.PSIsContainer -or
            ($DestinationItem.Attributes -band
                [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Admin User CLI destination is not a regular file: $Destination"
        } else {
            [IO.File]::Replace($Stage, $Destination, $Backup, $true)
        }
        $Published = Assert-SwawHarnessRegularFile `
            -Path $Destination `
            -Description 'published Admin User CLI executable' `
            -MaximumBytes $Contract.MaximumBytes
        if ([long]$Published.Length -ne [long]$Source.Length -or
            (Get-SwawHarnessFileSha256 -Path $Destination) -cne
                [string]$Source.Sha256) {
            throw 'Published Admin User CLI executable is corrupt.'
        }
    } finally {
        foreach ($WorkPath in @($Stage, $Backup)) {
            if (-not (Test-SwawHarnessPathExists -Path $WorkPath)) {
                continue
            }
            Remove-SwawHarnessControlledPathWithRetry `
                -Path $WorkPath `
                -ControlledRoot $DataHome `
                -Activity 'cleaning Admin User CLI publication work'
        }
    }
    return $Destination
}

function Initialize-SwawHarnessWindowsAdmin {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$BootstrapRelease,
        [Parameter(Mandatory = $true)][object]$HostModuleRelease
    )

    $UserCliPath = Publish-SwawHarnessAdminUserCli `
        -Context $Context `
        -BootstrapRelease $BootstrapRelease
    $VersionPointerPath = Publish-SwawHarnessAdminCoreHostVersionPointer `
        -Context $Context `
        -HostModuleRelease $HostModuleRelease
    return [pscustomobject][ordered]@{
        UserId = 'admin'
        UserCliPath = $UserCliPath
        HostModuleRelease = $HostModuleRelease
        HostVersionPointerPath = $VersionPointerPath
    }
}
