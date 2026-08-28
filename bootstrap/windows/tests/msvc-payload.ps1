[CmdletBinding()]
param([string]$RepositoryDataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$WindowsRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path $WindowsRoot 'builder\filesystem.ps1')
. (Join-Path $WindowsRoot 'toolchain\msvc\payload.ps1')

function Assert-MsvcPayloadTest {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function New-MsvcPayloadZip {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$Entries
    )

    $Stream = [IO.File]::Open(
        $Path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $Archive = [IO.Compression.ZipArchive]::new(
            $Stream,
            [IO.Compression.ZipArchiveMode]::Create,
            $true
        )
        try {
            foreach ($Name in $Entries.Keys) {
                $Entry = $Archive.CreateEntry([string]$Name)
                $Writer = [IO.StreamWriter]::new(
                    $Entry.Open(),
                    [Text.UTF8Encoding]::new($false)
                )
                try {
                    $Writer.Write([string]$Entries[$Name])
                } finally {
                    $Writer.Dispose()
                }
            }
        } finally {
            $Archive.Dispose()
        }
    } finally {
        $Stream.Dispose()
    }
}

$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $PSScriptRoot 'paths.ps1')
$RepositoryDataRoot = Resolve-SwawHarnessWindowsTestRepositoryDataRoot `
    -RepositoryDataRoot $RepositoryDataRoot `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -RepositoryDataRoot $RepositoryDataRoot
$TestBase = Split-Path -Path $TestRoot -Parent
try {
    $ArchivePath = Join-Path $TestRoot 'valid.vsix'
    New-MsvcPayloadZip -Path $ArchivePath -Entries ([ordered]@{
        'Contents/bin/tool.exe' = 'tool'
        'Contents/include/a%20b.h' = 'header'
        'ignored/secret.txt' = 'ignored'
    })
    $Destination = Join-Path $TestRoot 'expanded'
    Expand-SwawHarnessMsvcVsix `
        -ArchivePath $ArchivePath `
        -Destination $Destination `
        -ControlledRoot $TestRoot
    Assert-MsvcPayloadTest `
        -Condition (
            [IO.File]::ReadAllText((Join-Path $Destination 'bin\tool.exe')) -ceq
                'tool' -and
            [IO.File]::Exists((Join-Path $Destination 'include\a b.h')) -and
            -not [IO.File]::Exists((Join-Path $Destination 'secret.txt'))
        ) `
        -Message 'MSVC VSIX extraction lost its Contents-only contract.'

    $TraversalPath = Join-Path $TestRoot 'traversal.vsix'
    New-MsvcPayloadZip -Path $TraversalPath -Entries ([ordered]@{
        'Contents/../escape.txt' = 'escape'
    })
    $TraversalRejected = $false
    try {
        Expand-SwawHarnessMsvcVsix `
            -ArchivePath $TraversalPath `
            -Destination (Join-Path $TestRoot 'traversal') `
            -ControlledRoot $TestRoot
    } catch {
        $TraversalRejected = $_.Exception.Message -like '*escapes its root*'
    }
    Assert-MsvcPayloadTest `
        -Condition ($TraversalRejected -and
            -not [IO.File]::Exists((Join-Path $TestRoot 'escape.txt'))) `
        -Message 'MSVC VSIX extraction accepted path traversal.'

    $MsiArguments = @(Get-SwawHarnessMsvcAdministrativeInstallArguments `
        -MsiPath 'C:\source\sdk.msi' `
        -Destination 'C:\stage\msvc' `
        -LogPath 'C:\logs\sdk.log')
    Assert-MsvcPayloadTest `
        -Condition (
            $MsiArguments -ccontains '/quiet' -and
            $MsiArguments -ccontains '/qn' -and
            $MsiArguments -ccontains '/norestart' -and
            $MsiArguments -ccontains 'REBOOT=ReallySuppress'
        ) `
        -Message 'MSVC administrative install is not sealed as silent/no-restart.'

    Write-Host '[PASS] MSVC payload test' -ForegroundColor Green
} finally {
    Remove-SwawHarnessControlledPathWithRetry `
        -Path $TestRoot `
        -ControlledRoot $TestBase `
        -Activity 'cleaning the MSVC payload test'
}
