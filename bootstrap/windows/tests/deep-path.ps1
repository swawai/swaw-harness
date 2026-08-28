[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-DeepPathTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Deep-path test failed: $Message"
    }
}

if ($null -eq ('SwawHarnessNativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class SwawHarnessNativeMethods
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLink(
        string newFileName,
        string existingFileName,
        IntPtr securityAttributes);

    public static void CreateFileHardLink(string path, string target)
    {
        if (!CreateHardLink(path, target, IntPtr.Zero))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
}

function Copy-DeepPathSourceTree {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $RelativePaths = @(& git -C $SourceRoot `
        -c core.quotePath=false `
        ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0 -or $RelativePaths.Count -eq 0) {
        throw 'Cannot enumerate repository files for the deep-path fixture.'
    }
    foreach ($RelativePath in $RelativePaths) {
        $Source = Resolve-SwawHarnessChildPath `
            -Root $SourceRoot `
            -RelativePath ([string]$RelativePath) `
            -Description 'deep-path source file'
        if (-not [IO.File]::Exists($Source)) {
            continue
        }
        $Destination = Resolve-SwawHarnessChildPath `
            -Root $DestinationRoot `
            -RelativePath ([string]$RelativePath) `
            -Description 'deep-path fixture file'
        [void][IO.Directory]::CreateDirectory(
            (Split-Path -Path $Destination -Parent)
        )
        [IO.File]::Copy($Source, $Destination, $false)
    }
}

function Copy-DeepPathToolchainFixture {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    [void][IO.Directory]::CreateDirectory($DestinationRoot)
    $SourcePrefix = $SourceRoot.TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    foreach ($Item in Get-ChildItem -LiteralPath $SourceRoot -Recurse -Force) {
        if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Deep-path toolchain fixture rejects reparse points: $($Item.FullName)"
        }
        $RelativePath = $Item.FullName.Substring($SourcePrefix.Length)
        $Destination = Resolve-SwawHarnessChildPath `
            -Root $DestinationRoot `
            -RelativePath $RelativePath `
            -Description 'deep-path toolchain fixture entry'
        if ($Item.PSIsContainer) {
            [void][IO.Directory]::CreateDirectory($Destination)
            continue
        }
        [void][IO.Directory]::CreateDirectory(
            (Split-Path -Path $Destination -Parent)
        )
        [SwawHarnessNativeMethods]::CreateFileHardLink(
            $Destination,
            [string]$Item.FullName
        )
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\filesystem.ps1')
. (Join-Path $WindowsRoot 'builder\path-budget.ps1')
. (Join-Path $WindowsRoot 'builder\process.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$SourceContext = New-SwawHarnessWindowsBootstrapContext -DataRepo $DataRepo
$Contract = Read-SwawHarnessWindowsBootstrapContract `
    -Path (Join-Path $WindowsRoot 'contract.json')
$SourceToolchainRoot = Get-SwawHarnessToolchainTargetPath `
    -Context $SourceContext `
    -Contract $Contract
$SourceToolchain = Get-SwawHarnessValidToolchain `
    -Context $SourceContext `
    -Contract $Contract `
    -InstallRoot $SourceToolchainRoot
if ($null -eq $SourceToolchain) {
    throw 'Deep-path test requires the Contract toolchain to be installed.'
}

$FixtureParent = Split-Path -Path $RepositoryRoot -Parent
$Token = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$LeafPrefix = "swaw-harness-path-$Token-"
$LeafLength = 60 - $FixtureParent.Length - 1
if ($LeafLength -lt $LeafPrefix.Length) {
    throw "Cannot place a 60-character fixture below: $FixtureParent"
}
$DeepLeaf = $LeafPrefix + ('d' * ($LeafLength - $LeafPrefix.Length))
$DeepRoot = [IO.Path]::GetFullPath((Join-Path $FixtureParent $DeepLeaf))
$ParentPrefix = $FixtureParent.TrimEnd('\', '/') +
    [IO.Path]::DirectorySeparatorChar
if ($DeepRoot.Length -ne 60 -or
    -not $DeepRoot.StartsWith(
        $ParentPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
    throw "Deep-path fixture root is outside its verified parent: $DeepRoot"
}

try {
    [void][IO.Directory]::CreateDirectory($DeepRoot)
    Copy-DeepPathSourceTree `
        -SourceRoot $RepositoryRoot `
        -DestinationRoot $DeepRoot
    $DeepDataRepo = Join-Path $DeepRoot 'data.repo'
    $DeepContext = New-SwawHarnessWindowsBootstrapContext `
        -DataRepo $DeepDataRepo
    $DeepToolchainRoot = Join-Path $DeepContext.ToolchainRoot (
        [IO.Path]::GetFileName($SourceToolchain.Root)
    )
    Copy-DeepPathToolchainFixture `
        -SourceRoot $SourceToolchain.Root `
        -DestinationRoot $DeepToolchainRoot

    $Results = @(& (Join-Path $DeepRoot 'bootstrap\windows\main.ps1') `
        -DataRepo $DeepDataRepo)
    Assert-DeepPathTest `
        -Condition ($Results.Count -eq 1) `
        -Message 'deep Bootstrap did not return exactly one Release'
    $Release = $Results[0]
    $LongestNativePath = Assert-SwawHarnessNativeTreePathBudget `
        -Root $DeepContext.DataRepo `
        -Description 'Deep-path native tree'
    Assert-DeepPathTest `
        -Condition (
            $DeepRoot.Length -eq 60 -and
            ([string]$LongestNativePath).Length -le 240 -and
            $Release.Artifacts.Count -eq 3
        ) `
        -Message 'deep build exceeded its declared repository or native budget'

    foreach ($MutableRoot in @(
        $DeepContext.BuildRoot,
        $DeepContext.ToolchainRoot,
        $DeepContext.StageRoot,
        $DeepContext.CacheRoot
    )) {
        if (Test-SwawHarnessPathExists -Path $MutableRoot) {
            Remove-SwawHarnessControlledPathWithRetry `
                -Path $MutableRoot `
                -ControlledRoot $DeepDataRepo `
                -Activity 'making deep native build data unavailable at runtime'
        }
    }

    $Artifacts = @{}
    foreach ($Artifact in $Release.Artifacts) {
        $Artifacts[[string]$Artifact.Name] = [string]$Artifact.Path
    }
    $Core = Invoke-SwawHarnessCapturedProcess `
        -Executable $Artifacts['swaw-harness-helloworld.exe'] `
        -Arguments @('Deep') `
        -WorkingDirectory $Release.Root
    $Entry = Invoke-SwawHarnessCapturedProcess `
        -Executable $Artifacts['swaw-harness-entry.exe'] `
        -Arguments @() `
        -WorkingDirectory $Release.Root
    $EntryManager = Invoke-SwawHarnessCapturedProcess `
        -Executable $Artifacts['swaw-harness-entry-manager.exe'] `
        -Arguments @() `
        -WorkingDirectory $Release.Root
    Assert-DeepPathTest `
        -Condition (
            $Core.ExitCode -eq 0 -and
            $Core.Output -ceq 'Hello, Deep!' -and
            $Entry.ExitCode -eq 1 -and
            $Entry.Error -cmatch '^\[ERROR\] ' -and
            $EntryManager.ExitCode -eq 1 -and
            $EntryManager.Error -cmatch '^\[ERROR\] '
        ) `
        -Message 'published executables depended on unavailable native data'

    Write-Host (
        "[PASS] Windows Bootstrap 60-character deep path " +
        "(longest native path $(([string]$LongestNativePath).Length))"
    ) -ForegroundColor Green
} finally {
    if ([IO.Directory]::Exists($DeepRoot)) {
        Remove-SwawHarnessControlledPathWithRetry `
            -Path $DeepRoot `
            -ControlledRoot $FixtureParent `
            -Activity 'cleaning the deep-path fixture'
    }
}
