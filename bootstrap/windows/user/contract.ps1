Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')

function Get-SwawHarnessUserCliContractStrings {
    param(
        [Parameter(Mandatory = $true)][object[]]$Values,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    if ($Values.Count -eq 0 -or $Values.Count -gt 32) {
        throw "$Description must contain between 1 and 32 values."
    }
    $Result = [Collections.Generic.List[string]]::new()
    foreach ($Value in $Values) {
        $Text = [string]$Value
        if ($Text -cnotmatch $Pattern) {
            throw "$Description contains an invalid value: $Text"
        }
        $Result.Add($Text)
    }
    return [string[]]$Result.ToArray()
}

function Read-SwawHarnessWindowsUserCliContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId
    )

    $Contract = Read-SwawHarnessJsonFile `
        -Path $Path `
        -Description 'Windows User CLI executable build contract'
    Assert-SwawHarnessObjectFields `
        -Value $Contract `
        -Expected @(
            'schema', 'buildArtifact', 'artifact', 'source', 'compilerArguments',
            'linkerArguments', 'libraries', 'maximumBytes'
        ) `
        -Description 'Windows User CLI executable build contract'
    if ([string]$Contract.schema -cne 'swaw.harness.user-cli-build/v1') {
        throw 'Unsupported Windows User CLI executable build contract schema.'
    }
    if ($PlatformTargetId -cne 'x86_64-pc-windows-msvc') {
        throw 'Windows User CLI executable v1 supports x86_64-pc-windows-msvc only.'
    }
    $BuildArtifact = ([string]$Contract.buildArtifact).Trim()
    if ($BuildArtifact -cne 'swaw-har-user.exe') {
        throw 'Windows User CLI executable build artifact is invalid.'
    }
    $Artifact = ([string]$Contract.artifact).Trim()
    if ($Artifact -cne 'user.exe') {
        throw 'Windows User CLI executable artifact must be user.exe.'
    }
    $Source = ([string]$Contract.source).Trim()
    if ($Source -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.c$') {
        throw 'Windows User CLI executable source is invalid.'
    }
    [string[]]$CompilerArguments = Get-SwawHarnessUserCliContractStrings `
        -Values @($Contract.compilerArguments) `
        -Description 'Windows User CLI executable compiler arguments' `
        -Pattern '^/[A-Za-z0-9:._+-]+$'
    [string[]]$LinkerArguments = Get-SwawHarnessUserCliContractStrings `
        -Values @($Contract.linkerArguments) `
        -Description 'Windows User CLI executable linker arguments' `
        -Pattern '^/[A-Za-z0-9:._+-]+$'
    [string[]]$Libraries = Get-SwawHarnessUserCliContractStrings `
        -Values @($Contract.libraries) `
        -Description 'Windows User CLI executable libraries' `
        -Pattern '^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}\.lib$'
    $MaximumBytes = [long]$Contract.maximumBytes
    if ($MaximumBytes -le 0 -or $MaximumBytes -gt 1MB) {
        throw 'Windows User CLI executable maximumBytes is invalid.'
    }

    return [pscustomobject][ordered]@{
        Schema = [string]$Contract.schema
        Revision = Get-SwawHarnessFileSha256 -Path $Path
        PlatformTargetId = $PlatformTargetId
        BuildBinary = $BuildArtifact
        ProductBinary = $Artifact
        Source = $Source
        CompilerArguments = $CompilerArguments
        LinkerArguments = $LinkerArguments
        Libraries = $Libraries
        MaximumBytes = $MaximumBytes
    }
}
