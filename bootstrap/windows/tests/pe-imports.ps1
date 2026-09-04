Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')
. (Join-Path $PSScriptRoot '..\builder\process.ps1')

$script:SwawHarnessExternalCrtImportPattern = (
    '^(?i:(?:vcruntime|msvcp|msvcr|msvcm|ucrtbase|concrt|vccorlib|' +
    'vcomp|vcamp)[A-Za-z0-9_-]*|api-ms-win-crt-[A-Za-z0-9_-]+)\.dll$'
)

function Test-SwawHarnessExternalCrtImport {
    param([Parameter(Mandatory = $true)][string]$LibraryName)

    return $LibraryName -match $script:SwawHarnessExternalCrtImportPattern
}

function Get-SwawHarnessPeImportedLibraries {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$LinkerPath,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @()
    )

    $Artifact = Assert-SwawHarnessRegularFile `
        -Path $ArtifactPath `
        -Description 'PE import test artifact'
    [void](Assert-SwawHarnessRegularFile `
        -Path $LinkerPath `
        -Description 'MSVC linker executable')
    $Result = Invoke-SwawHarnessCapturedProcess `
        -Executable $LinkerPath `
        -Arguments @('/dump', '/nologo', '/imports', $Artifact.FullName) `
        -WorkingDirectory $Artifact.DirectoryName `
        -EnvironmentVariables $EnvironmentVariables `
        -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
        -TimeoutSeconds 120
    if ($Result.ExitCode -ne 0) {
        throw (
            "MSVC PE import inspection failed with exit code " +
            "$($Result.ExitCode). $($Result.Error) $($Result.Output)"
        ).Trim()
    }

    $Libraries = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    # link.exe emits CRLF. In .NET multiline mode, `$` stops before LF but not
    # before the preceding CR, so the optional CR must be consumed explicitly.
    $Pattern = '(?im)^[ \t]+([A-Za-z0-9][A-Za-z0-9._-]*\.dll)[ \t]*\r?$'
    foreach ($Match in [Text.RegularExpressions.Regex]::Matches(
        $Result.Output,
        $Pattern
    )) {
        [void]$Libraries.Add([string]$Match.Groups[1].Value)
    }
    if ($Libraries.Count -eq 0) {
        throw 'MSVC PE import inspection reported no imported libraries.'
    }
    return [string[]]@($Libraries)
}

function Assert-SwawHarnessNoExternalCrtImports {
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactPath,
        [Parameter(Mandatory = $true)][string]$LinkerPath,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @()
    )

    [string[]]$Libraries = @(Get-SwawHarnessPeImportedLibraries `
        -ArtifactPath $ArtifactPath `
        -LinkerPath $LinkerPath `
        -EnvironmentVariables $EnvironmentVariables `
        -UnsetEnvironmentVariables $UnsetEnvironmentVariables)
    $ExternalCrt = @($Libraries | Where-Object {
        Test-SwawHarnessExternalCrtImport -LibraryName $_
    })
    if ($ExternalCrt.Count -gt 0) {
        throw (
            'PE artifact imports an external C/C++ runtime: ' +
            [string]::Join(', ', [string[]]$ExternalCrt)
        )
    }
}
