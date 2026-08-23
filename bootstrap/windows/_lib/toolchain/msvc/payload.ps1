Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.IO.Compression.FileSystem

. (Join-Path $PSScriptRoot '..\download-cache.ps1')
. (Join-Path $PSScriptRoot '..\..\process.ps1')

function ConvertTo-SwawHarnessMsvcPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $FileName = [string]$Payload.fileName
    $LeafName = [IO.Path]::GetFileName($FileName)
    $Sha256 = ([string]$Payload.sha256).Trim().ToLowerInvariant()
    $DeclaredSize = [long]$Payload.size
    $Uri = $null
    if ([string]::IsNullOrWhiteSpace($FileName) -or
        [string]::IsNullOrWhiteSpace($LeafName) -or
        $LeafName -in @('.', '..') -or
        $LeafName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or
        $Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $DeclaredSize -le 0 -or $DeclaredSize -gt 4GB -or
        -not [Uri]::TryCreate(
            [string]$Payload.url,
            [UriKind]::Absolute,
            [ref]$Uri
        ) -or
        $Uri.Scheme -cne 'https' -or
        $Uri.Host -cne 'download.visualstudio.microsoft.com') {
        throw "Invalid Microsoft payload for $Description."
    }
    return [pscustomobject][ordered]@{
        FileName = $FileName
        LeafName = $LeafName
        Sha256 = $Sha256
        DeclaredSize = $DeclaredSize
        Url = $Uri.AbsoluteUri
    }
}

function Get-SwawHarnessMsvcVerifiedPayload {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Payload
    )

    $DeclaredSize = [long]$Payload.DeclaredSize
    $MaximumBytes = if ($DeclaredSize -gt 1GB) {
        4GB
    } else {
        [Math]::Max(64MB, $DeclaredSize * 4L)
    }
    $Path = Get-SwawHarnessVerifiedArtifact `
        -Context $Context `
        -Source ([string]$Payload.Url) `
        -ExpectedLength 0 `
        -ExpectedSha256 ([string]$Payload.Sha256) `
        -Description "Microsoft payload $($Payload.LeafName)" `
        -MaximumBytes $MaximumBytes
    $Item = Assert-SwawHarnessRegularFile `
        -Path $Path `
        -Description "Microsoft payload $($Payload.LeafName)" `
        -MaximumBytes $MaximumBytes
    return [pscustomobject][ordered]@{
        Path = $Path
        FileName = [string]$Payload.FileName
        LeafName = [string]$Payload.LeafName
        Url = [string]$Payload.Url
        DeclaredSize = $DeclaredSize
        Length = [long]$Item.Length
        Sha256 = [string]$Payload.Sha256
    }
}

function Copy-SwawHarnessMsvcPayloadToSourceRoot {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][string]$VerifiedPath,
        [Parameter(Mandatory = $true)][string]$SourceRoot
    )

    $SourceRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $SourceRoot `
        -Root $Context.CacheRoot `
        -Activity 'staging MSVC installer sources'
    [void][IO.Directory]::CreateDirectory($SourceRoot)
    $Destination = Resolve-SwawHarnessChildPath `
        -Root $SourceRoot `
        -RelativePath ([string]$Payload.LeafName) `
        -Description 'MSVC installer source'
    if ([IO.File]::Exists($Destination)) {
        if ((Get-SwawHarnessFileSha256 -Path $Destination) -cne
            [string]$Payload.Sha256) {
            throw "Conflicting MSVC installer source: $Destination"
        }
        return $Destination
    }
    $VerifiedItem = Assert-SwawHarnessRegularFile `
        -Path $VerifiedPath `
        -Description 'verified MSVC payload' `
        -MaximumBytes 4GB
    [IO.File]::Copy($VerifiedPath, $Destination, $false)
    $Item = Get-Item -LiteralPath $Destination -Force
    if ([long]$Item.Length -ne [long]$VerifiedItem.Length -or
        (Get-SwawHarnessFileSha256 -Path $Destination) -cne
            [string]$Payload.Sha256) {
        Remove-SwawHarnessControlledPath `
            -Path $Destination `
            -ControlledRoot $Context.CacheRoot `
            -Activity 'removing an invalid MSVC source copy'
        throw "MSVC source copy verification failed: $Destination"
    }
    return $Destination
}

function Expand-SwawHarnessMsvcVsix {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    [void](Assert-SwawHarnessRegularFile `
        -Path $ArchivePath `
        -Description 'MSVC VSIX payload' `
        -MaximumBytes 4GB)
    $Destination = Assert-SwawHarnessPathInsideRoot `
        -Path $Destination `
        -Root $ControlledRoot `
        -Activity 'extracting an MSVC VSIX'
    [void][IO.Directory]::CreateDirectory($Destination)
    $Archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $Targets = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $EntryCount = 0
    [long]$TotalBytes = 0
    try {
        foreach ($Entry in $Archive.Entries) {
            if (-not $Entry.FullName.StartsWith(
                'Contents/',
                [StringComparison]::OrdinalIgnoreCase
            )) {
                continue
            }
            $EntryCount++
            $TotalBytes += [long]$Entry.Length
            if ($EntryCount -gt 200000 -or
                $Entry.Length -gt 4GB -or $TotalBytes -gt 12GB) {
                throw 'MSVC VSIX exceeds extraction safety limits.'
            }
            $UnixType = (($Entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($UnixType -eq 0xA000) {
                throw "MSVC VSIX cannot contain a symbolic link: $($Entry.FullName)"
            }
            $Encoded = $Entry.FullName.Substring('Contents/'.Length)
            if ([string]::IsNullOrWhiteSpace($Encoded)) {
                continue
            }
            $RelativePath = [Uri]::UnescapeDataString($Encoded).Replace(
                '/',
                [IO.Path]::DirectorySeparatorChar
            )
            $Target = Resolve-SwawHarnessChildPath `
                -Root $Destination `
                -RelativePath $RelativePath `
                -Description 'MSVC VSIX entry'
            if (-not $Targets.Add($Target)) {
                throw "MSVC VSIX contains a duplicate target: $RelativePath"
            }
            if ($Entry.FullName.EndsWith('/')) {
                [void][IO.Directory]::CreateDirectory($Target)
                continue
            }
            [void][IO.Directory]::CreateDirectory(
                (Split-Path -Path $Target -Parent)
            )
            $Input = $Entry.Open()
            try {
                $Output = [IO.File]::Open(
                    $Target,
                    [IO.FileMode]::Create,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::None
                )
                try {
                    $Input.CopyTo($Output)
                } finally {
                    $Output.Dispose()
                }
            } finally {
                $Input.Dispose()
            }
        }
    } finally {
        $Archive.Dispose()
    }
    if ($EntryCount -eq 0) {
        throw "VSIX has no Contents payload: $ArchivePath"
    }
}

function Get-SwawHarnessMsvcCabNames {
    param(
        [Parameter(Mandatory = $true)][string]$MsiPath,
        [Parameter(Mandatory = $true)][string[]]$CandidateNames
    )

    [void](Assert-SwawHarnessRegularFile `
        -Path $MsiPath `
        -Description 'Windows SDK MSI' `
        -MaximumBytes 512MB)
    $Text = [Text.Encoding]::ASCII.GetString(
        [IO.File]::ReadAllBytes($MsiPath)
    )
    $Names = foreach ($Candidate in $CandidateNames) {
        if ([string]::IsNullOrWhiteSpace($Candidate) -or
            [IO.Path]::GetExtension($Candidate) -ine '.cab' -or
            [IO.Path]::GetFileName($Candidate) -cne $Candidate) {
            throw "Invalid Windows SDK CAB candidate: $Candidate"
        }
        if ($Text.IndexOf(
            $Candidate,
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0) {
            $Candidate
        }
    }
    return [string[]]@($Names | Sort-Object -Unique)
}

function Get-SwawHarnessMsvcAdministrativeInstallArguments {
    param(
        [Parameter(Mandatory = $true)][string]$MsiPath,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$LogPath
    )

    return [string[]]@(
        '/a', $MsiPath, '/quiet', '/qn', '/norestart',
        'REBOOT=ReallySuppress', "TARGETDIR=$Destination", '/l*v', $LogPath
    )
}

function Invoke-SwawHarnessMsvcAdministrativeInstall {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$MsiPath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $Destination = Assert-SwawHarnessPathInsideRoot `
        -Path $Destination `
        -Root $Context.CacheRoot `
        -Activity 'installing an MSVC payload'
    $LogName = "$([IO.Path]::GetFileName($MsiPath)).install.log"
    $LogPath = Assert-SwawHarnessPathInsideRoot `
        -Path (Join-Path $Context.LogRoot $LogName) `
        -Root $Context.CacheRoot `
        -Activity 'writing an MSVC installation log'
    [void][IO.Directory]::CreateDirectory($Destination)
    [void][IO.Directory]::CreateDirectory((Split-Path $LogPath -Parent))
    if ([IO.File]::Exists($LogPath)) {
        [IO.File]::Delete($LogPath)
    }
    $MsiExec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    [void](Assert-SwawHarnessRegularFile `
        -Path $MsiExec `
        -Description 'Windows Installer')
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $MsiExec `
        -Arguments (Get-SwawHarnessMsvcAdministrativeInstallArguments `
            -MsiPath $MsiPath `
            -Destination $Destination `
            -LogPath $LogPath) `
        -WorkingDirectory (Split-Path $MsiPath -Parent) `
        -TimeoutSeconds 600
    if ($Result.ExitCode -ne 0) {
        throw (
            "Windows Installer exited with code $($Result.ExitCode) for " +
            "$MsiPath. Diagnostic log: $LogPath. $($Result.Error)"
        )
    }
    if ([IO.File]::Exists($LogPath)) {
        [IO.File]::Delete($LogPath)
    }
}
