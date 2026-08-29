Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\context.ps1')
. (Join-Path $PSScriptRoot '..\builder\contract.ps1')
. (Join-Path $PSScriptRoot '..\builder\process.ps1')
. (Join-Path $PSScriptRoot '..\builder\path-budget.ps1')
. (Join-Path $PSScriptRoot '..\builder\build\candidate.ps1')
. (Join-Path $PSScriptRoot '..\builder\filesystem.ps1')
. (Join-Path $PSScriptRoot 'contract.ps1')

$script:SwawHarnessWindowsEntryRoot = $PSScriptRoot

function Invoke-SwawHarnessWindowsEntryCandidateBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$CompilerPath,
        [Parameter(Mandatory = $true)][string]$LinkerPath,
        [Collections.IDictionary]$EnvironmentVariables = @{},
        [string[]]$UnsetEnvironmentVariables = @()
    )

    $EntryRoot = $script:SwawHarnessWindowsEntryRoot
    [void](Assert-SwawHarnessRepositoryRootPathBudget `
        -RepositoryRoot (Join-Path $EntryRoot '..\..\..'))
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $EntryRoot '..\contract.json')
    $Contract = Read-SwawHarnessWindowsEntryContract `
        -Path (Join-Path $EntryRoot 'contract.json') `
        -PlatformTargetId $PlatformContract.PlatformTargetId
    $BuildRoot = Join-Path $Context.BuildRoot 'entry'
    $BuildRoot = Assert-SwawHarnessPathInsideRoot `
        -Path $BuildRoot `
        -Root $Context.BuildRoot `
        -Activity 'building the Windows Entry executable candidate'
    [void][IO.Directory]::CreateDirectory($BuildRoot)

    $CompilerPath = Get-SwawHarnessFullPath -Path $CompilerPath
    $LinkerPath = Get-SwawHarnessFullPath -Path $LinkerPath
    [void](Assert-SwawHarnessRegularFile `
        -Path $CompilerPath `
        -Description 'C compiler executable')
    [void](Assert-SwawHarnessRegularFile `
        -Path $LinkerPath `
        -Description 'linker executable')

    $Lock = Enter-SwawHarnessFileLock `
        -Path (Join-Path $Context.LockRoot (
            "build-entry-$($Contract.PlatformTargetId).lock"
        )) `
        -ControlledRoot $Context.DataRepo `
        -TimeoutSeconds 1800
    try {
        $OutputRoot = $BuildRoot
        [void][IO.Directory]::CreateDirectory($OutputRoot)
        $ObjectPath = Join-Path $OutputRoot 'entry.obj'
        $ArtifactPath = Join-Path $OutputRoot $Contract.BuildBinary
        foreach ($OutputPath in @($ObjectPath, $ArtifactPath)) {
            if (Test-SwawHarnessPathExists -Path $OutputPath) {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path $OutputPath `
                    -ControlledRoot $Context.BuildRoot `
                    -Activity 'replacing an Entry executable build output'
            }
        }

        $SourcePath = Resolve-SwawHarnessChildPath `
            -Root $EntryRoot `
            -RelativePath $Contract.Source `
            -Description 'Windows Entry executable source'
        [void](Assert-SwawHarnessRegularFile `
            -Path $SourcePath `
            -Description 'Windows Entry executable source' `
            -MaximumBytes 1MB)
        [void](Assert-SwawHarnessNativePathBudget `
            -Paths @(
                $CompilerPath, $LinkerPath, $SourcePath,
                $ObjectPath, $ArtifactPath, $OutputRoot
            ) `
            -Description 'Planned Entry native build path')
        $CompileResult = Invoke-SwawHarnessCapturedProcess `
            -Executable $CompilerPath `
            -Arguments @(
                $Contract.CompilerArguments
                "/Fo$ObjectPath"
                $SourcePath
            ) `
            -WorkingDirectory $EntryRoot `
            -EnvironmentVariables $EnvironmentVariables `
            -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
            -TimeoutSeconds 300
        if ($CompileResult.ExitCode -ne 0) {
            throw (
                'Entry executable compilation failed with exit code ' +
                "$($CompileResult.ExitCode). $($CompileResult.Error) " +
                "$($CompileResult.Output)"
            ).Trim()
        }
        [void](Assert-SwawHarnessRegularFile `
            -Path $ObjectPath `
            -Description 'Windows Entry executable object')

        $LinkResult = Invoke-SwawHarnessCapturedProcess `
            -Executable $LinkerPath `
            -Arguments @(
                $Contract.LinkerArguments
                "/out:$ArtifactPath"
                $ObjectPath
                $Contract.Libraries
            ) `
            -WorkingDirectory $OutputRoot `
            -EnvironmentVariables $EnvironmentVariables `
            -UnsetEnvironmentVariables $UnsetEnvironmentVariables `
            -TimeoutSeconds 300
        if ($LinkResult.ExitCode -ne 0) {
            throw (
                "Entry executable link failed with exit code " +
                "$($LinkResult.ExitCode). $($LinkResult.Error) " +
                "$($LinkResult.Output)"
            ).Trim()
        }
        [void](Assert-SwawHarnessNativeTreePathBudget `
            -Root $OutputRoot `
            -Description 'Entry native output path')
        $Artifact = Assert-SwawHarnessRegularFile `
            -Path $ArtifactPath `
            -Description 'Built Windows Entry executable' `
            -MaximumBytes $Contract.MaximumBytes
        if ([long]$Artifact.Length -le 0) {
            throw 'Built Windows Entry executable is empty.'
        }
        $CandidateRoot = Publish-SwawHarnessBootstrapCandidate `
            -ArtifactPath $ArtifactPath `
            -Contract $Contract `
            -BuildRoot $BuildRoot `
            -ControlledRoot $Context.BuildRoot
        Write-Host "[BUILT] $ArtifactPath" -ForegroundColor Green
        Write-Output $CandidateRoot
    } finally {
        $Lock.Dispose()
    }
}
