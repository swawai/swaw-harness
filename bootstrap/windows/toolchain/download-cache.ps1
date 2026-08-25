Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')
. (Join-Path $PSScriptRoot '..\builder\filesystem.ps1')

Add-Type -AssemblyName System.Net.Http

function Get-SwawHarnessSourceFileName {
    param([Parameter(Mandatory = $true)][string]$Source)

    if ([IO.File]::Exists($Source)) {
        return [IO.Path]::GetFileName(
            (Get-SwawHarnessFullPath -Path $Source)
        )
    }
    $Uri = $null
    if (-not [Uri]::TryCreate($Source, [UriKind]::Absolute, [ref]$Uri) -or
        $Uri.Scheme -cne 'https') {
        throw "Invalid HTTPS download source: $Source"
    }
    $Name = [Uri]::UnescapeDataString(
        [IO.Path]::GetFileName($Uri.AbsolutePath)
    )
    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Cannot determine the artifact name from: $Source"
    }
    return $Name
}

function Remove-SwawHarnessDownloadTemporaryFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    if ([IO.File]::Exists($Path)) {
        $Path = Assert-SwawHarnessPathInsideRoot `
            -Path $Path `
            -Root $ControlledRoot `
            -Activity 'cleaning a download temporary file'
        [IO.File]::Delete($Path)
    }
}

function Remove-SwawHarnessOrphanedDownloads {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$ArtifactName,
        [Parameter(Mandatory = $true)][string]$ControlledRoot
    )

    $Directory = Assert-SwawHarnessPathInsideRoot `
        -Path $Directory `
        -Root $ControlledRoot `
        -Activity 'cleaning orphaned downloads'
    if (-not [IO.Directory]::Exists($Directory)) {
        return
    }
    $Prefix = ".$ArtifactName."
    foreach ($Path in [IO.Directory]::EnumerateFiles($Directory)) {
        $Name = [IO.Path]::GetFileName($Path)
        if (-not $Name.StartsWith($Prefix, [StringComparison]::Ordinal) -or
            -not $Name.EndsWith('.tmp', [StringComparison]::Ordinal)) {
            continue
        }
        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Download temporary file cannot be a reparse point: $Path"
        }
        [IO.File]::Delete($Path)
    }
}

function Copy-SwawHarnessBoundedStream {
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$InputStream,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][long]$MaximumBytes
    )

    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 4GB) {
        throw 'Download byte budget must be between 1 byte and 4 GiB.'
    }
    $Output = [IO.File]::Open(
        $Destination,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    [long]$TotalBytes = 0
    try {
        [byte[]]$Buffer = [byte[]]::new(65536)
        while ($true) {
            $Read = $InputStream.Read($Buffer, 0, $Buffer.Length)
            if ($Read -eq 0) {
                break
            }
            if ($TotalBytes -gt ($MaximumBytes - $Read)) {
                throw "Download exceeds its $MaximumBytes byte budget."
            }
            $Output.Write($Buffer, 0, $Read)
            $TotalBytes += $Read
        }
    } finally {
        $Output.Dispose()
    }
    if ($TotalBytes -eq 0) {
        throw 'The downloaded artifact is empty.'
    }
    return $TotalBytes
}

function Invoke-SwawHarnessHttpsDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][long]$MaximumBytes
    )

    $Uri = $null
    if (-not [Uri]::TryCreate($Source, [UriKind]::Absolute, [ref]$Uri) -or
        $Uri.Scheme -cne 'https') {
        throw "Invalid HTTPS download source: $Source"
    }
    $PreviousProtocol = [Net.ServicePointManager]::SecurityProtocol
    $Handler = $null
    $Client = $null
    $Response = $null
    $InputStream = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            $PreviousProtocol -bor [Net.SecurityProtocolType]::Tls12
        $Handler = [Net.Http.HttpClientHandler]::new()
        $Handler.AllowAutoRedirect = $true
        $Handler.MaxAutomaticRedirections = 10
        $Client = [Net.Http.HttpClient]::new($Handler)
        $Client.Timeout = [TimeSpan]::FromSeconds(900)
        $Client.DefaultRequestHeaders.UserAgent.ParseAdd(
            'Swaw-Harness-Bootstrap/2'
        )
        $Response = $Client.GetAsync(
            $Uri,
            [Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        [void]$Response.EnsureSuccessStatusCode()
        $FinalUri = $Response.RequestMessage.RequestUri
        if ($null -eq $FinalUri -or $FinalUri.Scheme -cne 'https') {
            throw 'HTTPS download redirected to an untrusted scheme.'
        }
        $ContentLength = $Response.Content.Headers.ContentLength
        if ($null -ne $ContentLength -and
            [long]$ContentLength -gt $MaximumBytes) {
            throw "Download exceeds its $MaximumBytes byte budget."
        }
        $InputStream = $Response.Content.ReadAsStreamAsync().
            GetAwaiter().GetResult()
        [void](Copy-SwawHarnessBoundedStream `
            -InputStream $InputStream `
            -Destination $Destination `
            -MaximumBytes $MaximumBytes)
    } finally {
        if ($null -ne $InputStream) {
            $InputStream.Dispose()
        }
        if ($null -ne $Response) {
            $Response.Dispose()
        }
        if ($null -ne $Client) {
            $Client.Dispose()
        }
        if ($null -ne $Handler) {
            $Handler.Dispose()
        }
        [Net.ServicePointManager]::SecurityProtocol = $PreviousProtocol
    }
}

function Invoke-SwawHarnessDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][long]$MaximumBytes
    )

    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 4GB) {
        throw 'Download byte budget must be between 1 byte and 4 GiB.'
    }
    $Destination = Assert-SwawHarnessPathInsideRoot `
        -Path $Destination `
        -Root $ControlledRoot `
        -Activity 'downloading a Bootstrap artifact'
    $Parent = Split-Path -Path $Destination -Parent
    [void][IO.Directory]::CreateDirectory($Parent)
    $TemporaryPath = Join-Path $Parent (
        ".$([IO.Path]::GetFileName($Destination))." +
        "$([Guid]::NewGuid().ToString('N')).tmp"
    )
    $ArtifactName = [IO.Path]::GetFileName($Destination)
    Write-Host "[DL] $ArtifactName" -ForegroundColor DarkGray

    try {
        if ([IO.File]::Exists($Source)) {
            $SourcePath = Get-SwawHarnessFullPath -Path $Source
            [void](Assert-SwawHarnessRegularFile `
                -Path $SourcePath `
                -Description 'local Bootstrap artifact' `
                -MaximumBytes $MaximumBytes)
            $InputStream = [IO.File]::OpenRead($SourcePath)
            try {
                [void](Copy-SwawHarnessBoundedStream `
                    -InputStream $InputStream `
                    -Destination $TemporaryPath `
                    -MaximumBytes $MaximumBytes)
            } finally {
                $InputStream.Dispose()
            }
        } else {
            $Failures = [Collections.Generic.List[string]]::new()
            for ($Attempt = 1; $Attempt -le 3; $Attempt++) {
                try {
                    Invoke-SwawHarnessHttpsDownload `
                        -Source $Source `
                        -Destination $TemporaryPath `
                        -MaximumBytes $MaximumBytes
                    break
                } catch {
                    $Failures.Add(
                        "attempt $Attempt`: $($_.Exception.Message)"
                    )
                    Remove-SwawHarnessDownloadTemporaryFile `
                        -Path $TemporaryPath `
                        -ControlledRoot $ControlledRoot
                    if ($Attempt -lt 3) {
                        Start-Sleep -Seconds 2
                    }
                }
            }
            if (-not [IO.File]::Exists($TemporaryPath)) {
                throw [string]::Join('; ', $Failures.ToArray())
            }
        }

        $Item = Get-Item `
            -LiteralPath $TemporaryPath `
            -Force `
            -ErrorAction SilentlyContinue
        if ($null -eq $Item -or $Item.PSIsContainer -or
            ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $Item.Length -le 0 -or $Item.Length -gt $MaximumBytes) {
            throw 'The downloaded artifact is empty or unsafe.'
        }
        [IO.File]::Move($TemporaryPath, $Destination)
    } catch {
        throw "Download failed for '$Source': $($_.Exception.Message)"
    } finally {
        Remove-SwawHarnessDownloadTemporaryFile `
            -Path $TemporaryPath `
            -ControlledRoot $ControlledRoot
    }
}

function Get-SwawHarnessVerifiedArtifact {
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][long]$ExpectedLength,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$Description,
        [long]$MaximumBytes = 4294967296
    )

    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 4GB -or
        $ExpectedLength -lt 0 -or $ExpectedLength -gt $MaximumBytes -or
        $ExpectedSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw "$Description has an invalid pinned identity."
    }
    $Name = Get-SwawHarnessSourceFileName -Source $Source
    if ($Name -in @('.', '..') -or
        $Name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "$Description has an invalid file name: $Name"
    }
    $ArtifactRoot = Join-Path $Context.DownloadRoot (
        "sha256\$($ExpectedSha256.Substring(0, 2))\$ExpectedSha256"
    )
    $ArtifactRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $ArtifactRoot `
        -Root $Context.BootstrapWindowsCacheRoot `
        -Activity "using the $Description cache"
    $Path = Join-Path $ArtifactRoot $Name
    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot "artifact-$ExpectedSha256.lock") `
        -ControlledRoot $Context.BootstrapWindowsRoot
    try {
        if ([IO.File]::Exists($ArtifactRoot)) {
            Remove-SwawHarnessControlledPath `
                -Path $ArtifactRoot `
                -ControlledRoot $Context.BootstrapWindowsCacheRoot `
                -Activity "repairing the $Description cache root"
        }
        [void][IO.Directory]::CreateDirectory($ArtifactRoot)
        Remove-SwawHarnessOrphanedDownloads `
            -Directory $ArtifactRoot `
            -ArtifactName $Name `
            -ControlledRoot $Context.BootstrapWindowsCacheRoot
        if ([IO.Directory]::Exists($Path)) {
            Remove-SwawHarnessControlledPath `
                -Path $Path `
                -ControlledRoot $Context.BootstrapWindowsCacheRoot `
                -Activity "repairing the $Description cache"
        }
        if ([IO.File]::Exists($Path)) {
            $Item = Get-Item -LiteralPath $Path -Force
            $Valid = (
                ($Item.Attributes -band
                    [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                [long]$Item.Length -gt 0 -and
                [long]$Item.Length -le $MaximumBytes -and
                ($ExpectedLength -eq 0 -or
                    [long]$Item.Length -eq $ExpectedLength) -and
                (Get-SwawHarnessFileSha256 -Path $Path) -ceq
                    $ExpectedSha256
            )
            if (-not $Valid) {
                Remove-SwawHarnessControlledPath `
                    -Path $Path `
                    -ControlledRoot $Context.BootstrapWindowsCacheRoot `
                    -Activity "removing a corrupt $Description cache"
            }
        }
        if (-not [IO.File]::Exists($Path)) {
            Invoke-SwawHarnessDownload `
                -Source $Source `
                -Destination $Path `
                -ControlledRoot $Context.BootstrapWindowsCacheRoot `
                -MaximumBytes $MaximumBytes
        }
        $Item = Assert-SwawHarnessRegularFile `
            -Path $Path `
            -Description $Description `
            -MaximumBytes $MaximumBytes
        if (($ExpectedLength -gt 0 -and
                [long]$Item.Length -ne $ExpectedLength) -or
            (Get-SwawHarnessFileSha256 -Path $Path) -cne
                $ExpectedSha256) {
            Remove-SwawHarnessControlledPath `
                -Path $Path `
                -ControlledRoot $Context.BootstrapWindowsCacheRoot `
                -Activity "removing an unverified $Description"
            throw "$Description verification failed: $Name"
        }
        return $Path
    } finally {
        $Lock.Dispose()
    }
}
