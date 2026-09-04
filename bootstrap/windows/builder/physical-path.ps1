Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'foundation.ps1')

if ($null -eq ('SwawHarnessPathNativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class SwawHarnessPathNativeMethods
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(
        SafeFileHandle file,
        StringBuilder path,
        uint pathLength,
        uint flags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode,
        SetLastError = true)]
    private static extern uint QueryDosDevice(
        string deviceName,
        StringBuilder targetPath,
        int maximumLength);

    private static string GetExtendedPath(string path)
    {
        if (path.StartsWith(@"\\?\", StringComparison.Ordinal))
        {
            return path;
        }
        if (path.StartsWith(@"\\", StringComparison.Ordinal))
        {
            return @"\\?\UNC\" + path.Substring(2);
        }
        return @"\\?\" + path;
    }

    public static string GetFinalDirectoryPath(string path)
    {
        using (SafeFileHandle handle = CreateFile(
            GetExtendedPath(path),
            0,
            7,
            IntPtr.Zero,
            3,
            0x02000000,
            IntPtr.Zero))
        {
            if (handle.IsInvalid)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            int capacity = 512;
            while (true)
            {
                StringBuilder result = new StringBuilder(capacity);
                uint length = GetFinalPathNameByHandle(
                    handle, result, (uint)result.Capacity, 0);
                if (length == 0)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
                if (length < result.Capacity)
                {
                    return result.ToString();
                }
                capacity = checked((int)length + 1);
            }
        }
    }

    public static string GetDosDeviceTarget(string deviceName)
    {
        StringBuilder result = new StringBuilder(32768);
        if (QueryDosDevice(deviceName, result, result.Capacity) == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        return result.ToString();
    }
}
'@
}

function ConvertFrom-SwawHarnessExtendedWindowsPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $Path.Substring(8)
    }
    if ($Path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(4)
    }
    return $Path
}

function Assert-SwawHarnessPhysicalRepositoryRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $RepositoryRoot = Get-SwawHarnessFullPath -Path $RepositoryRoot
    $RootItem = Get-Item `
        -LiteralPath $RepositoryRoot `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $RootItem -or -not $RootItem.PSIsContainer) {
        throw "Windows Bootstrap repository root must exist: $RepositoryRoot"
    }

    $PathRoot = [IO.Path]::GetPathRoot($RepositoryRoot)
    if ($PathRoot -cmatch '^[A-Za-z]:[\\/]') {
        $DeviceName = $PathRoot.Substring(0, 2)
        $DeviceTarget = [SwawHarnessPathNativeMethods]::GetDosDeviceTarget(
            $DeviceName
        )
        if ($DeviceTarget.StartsWith(
            '\??\',
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw (
                'Windows Bootstrap repository root must not use a mapped ' +
                "drive: $DeviceName -> $DeviceTarget"
            )
        }
    }

    $Current = $RepositoryRoot
    while ($Current.Length -gt $PathRoot.Length) {
        $Item = Get-Item -LiteralPath $Current -Force -ErrorAction Stop
        if (($Item.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw (
                'Windows Bootstrap repository root must not use a reparse ' +
                "point: $Current"
            )
        }
        $Parent = Split-Path -Path $Current -Parent
        if ([string]::IsNullOrWhiteSpace($Parent) -or
            $Parent.Equals($Current, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $Current = $Parent
    }

    try {
        $FinalPath = [SwawHarnessPathNativeMethods]::GetFinalDirectoryPath(
            $RepositoryRoot
        )
    } catch {
        throw (
            'Windows Bootstrap could not resolve the repository root to its ' +
            "physical path: $RepositoryRoot. $($_.Exception.Message)"
        )
    }
    $FinalPath = Get-SwawHarnessFullPath -Path (
        ConvertFrom-SwawHarnessExtendedWindowsPath -Path $FinalPath
    )
    if (-not $FinalPath.Equals(
        $RepositoryRoot,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw (
            'Windows Bootstrap repository root must use its direct long ' +
            "physical path; '$RepositoryRoot' resolves to '$FinalPath'. " +
            'Drive mappings, reparse points, and 8.3 names are unsupported.'
        )
    }
    return $RepositoryRoot
}
