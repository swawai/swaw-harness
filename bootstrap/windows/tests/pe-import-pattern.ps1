[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-PeImportPatternTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "PE import pattern test failed: $Message"
    }
}

. (Join-Path $PSScriptRoot 'pe-imports.ps1')

$ExternalCrtLibraries = @(
    'VCRUNTIME140.dll',
    'VCRUNTIME140_1D.dll',
    'msvcp140_atomic_wait.dll',
    'msvcr120.dll',
    'msvcm90d.dll',
    'ucrtbase.dll',
    'ucrtbased.dll',
    'concrt140.dll',
    'vccorlib140.dll',
    'vcomp140.dll',
    'vcamp140.dll',
    'api-ms-win-crt-runtime-l1-1-0.dll'
)
foreach ($LibraryName in $ExternalCrtLibraries) {
    Assert-PeImportPatternTest `
        -Condition (Test-SwawHarnessExternalCrtImport `
            -LibraryName $LibraryName) `
        -Message "external runtime was allowed: $LibraryName"
}

$SystemLibraries = @(
    'KERNEL32.dll',
    'ntdll.dll',
    'USER32.dll',
    'api-ms-win-core-synch-l1-2-0.dll'
)
foreach ($LibraryName in $SystemLibraries) {
    Assert-PeImportPatternTest `
        -Condition (-not (Test-SwawHarnessExternalCrtImport `
            -LibraryName $LibraryName)) `
        -Message "system library was rejected: $LibraryName"
}

Write-Host '[PASS] Windows PE external CRT import classification' `
    -ForegroundColor Green
