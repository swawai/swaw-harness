[CmdletBinding()]
param([string]$DataRepo = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-BuildDeterminismTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Build determinism test failed: $Message"
    }
}

function Invoke-BuildDeterminismPass {
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Plan
    )

    $CoreCandidatePath = Invoke-SwawHarnessWindowsCoreCandidateBuild `
        -Context $Context `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $EntryCandidatePath = Invoke-SwawHarnessWindowsEntryCandidateBuild `
        -Context $Context `
        -CompilerPath $Plan.CompilerPath `
        -LinkerPath $Plan.LinkerPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables |
        Select-Object -Last 1
    $ManagerCandidatePaths = @(
        Invoke-SwawHarnessWindowsEntryManagerCandidateBuild `
        -Context $Context `
        -CargoPath $Plan.CargoPath `
        -EnvironmentVariables $Plan.EnvironmentVariables `
        -UnsetEnvironmentVariables $Plan.UnsetEnvironmentVariables
    )

    return Publish-SwawHarnessWindowsProducts `
        -Context $Context `
        -CoreCandidatePath ([string]$CoreCandidatePath) `
        -EntryCandidatePath ([string]$EntryCandidatePath) `
        -EntryManagerCandidatePaths $ManagerCandidatePaths
}

function Get-BuildDeterminismSnapshot {
    param([Parameter(Mandatory = $true)]$Release)

    return @($Release.Artifacts |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject][ordered]@{
                Name = [string]$_.Name
                Length = [long]$_.Length
                Sha256 = [string]$_.Sha256
            }
        })
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'builder\filesystem.ps1')
. (Join-Path $WindowsRoot 'publication.ps1')
. (Join-Path $WindowsRoot 'core\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry\candidate-build.ps1')
. (Join-Path $WindowsRoot 'entry.manager\candidate-build.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $WindowsRoot 'toolchain\environment.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$DataRepo = Resolve-SwawHarnessWindowsTestDataRepo `
    -DataRepo $DataRepo `
    -RepositoryRoot $RepositoryRoot
$TestRoot = New-SwawHarnessWindowsTestRunRoot -DataRepo $DataRepo
try {
    $SharedContext = New-SwawHarnessWindowsBootstrapContext `
        -DataRepo $DataRepo
    $PlatformContract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $InstallRoot = Get-SwawHarnessToolchainTargetPath `
        -Context $SharedContext `
        -Contract $PlatformContract
    $Toolchain = Get-SwawHarnessValidToolchain `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -InstallRoot $InstallRoot
    if ($null -eq $Toolchain) {
        throw 'Build determinism test requires the Contract toolchain.'
    }
    $Plan = Get-SwawHarnessToolchainEnvironment `
        -Context $SharedContext `
        -Contract $PlatformContract `
        -Toolchain $Toolchain
    $Context = New-SwawHarnessWindowsBootstrapContext -DataRepo $TestRoot

    $First = Invoke-BuildDeterminismPass `
        -Context $Context `
        -Plan $Plan
    $FirstSnapshot = @(Get-BuildDeterminismSnapshot -Release $First)
    $FirstCreated = (Get-Item -LiteralPath $First.Root).CreationTimeUtc
    $FirstSelector = [IO.File]::ReadAllText(
        [string]$First.SelectorPath,
        [Text.Encoding]::UTF8
    )

    Remove-SwawHarnessControlledPathWithRetry `
        -Path $Context.BuildRoot `
        -ControlledRoot $TestRoot `
        -Activity 'forcing a second clean Windows Bootstrap build'
    Start-Sleep -Milliseconds 1200

    $Second = Invoke-BuildDeterminismPass `
        -Context $Context `
        -Plan $Plan
    $SecondSnapshot = @(Get-BuildDeterminismSnapshot -Release $Second)
    $SecondCreated = (Get-Item -LiteralPath $Second.Root).CreationTimeUtc
    $SecondSelector = [IO.File]::ReadAllText(
        [string]$Second.SelectorPath,
        [Text.Encoding]::UTF8
    )

    Assert-BuildDeterminismTest `
        -Condition (
            $FirstSnapshot.Count -eq 4 -and
            $SecondSnapshot.Count -eq 4
        ) `
        -Message 'a clean build did not produce exactly four artifacts'
    $Differences = [Collections.Generic.List[string]]::new()
    for ($Index = 0; $Index -lt $FirstSnapshot.Count; $Index++) {
        $FirstArtifact = $FirstSnapshot[$Index]
        $SecondArtifact = $SecondSnapshot[$Index]
        if ($FirstArtifact.Name -cne $SecondArtifact.Name -or
            $FirstArtifact.Length -ne $SecondArtifact.Length -or
            $FirstArtifact.Sha256 -cne $SecondArtifact.Sha256) {
            $Differences.Add(
                "$($FirstArtifact.Name): $($FirstArtifact.Sha256) / " +
                $SecondArtifact.Sha256
            )
        }
    }
    Assert-BuildDeterminismTest `
        -Condition ($Differences.Count -eq 0) `
        -Message (
            'clean builds produced different artifacts: ' +
            [string]::Join('; ', $Differences)
        )

    $ReleaseDirectories = @(
        Get-ChildItem `
            -LiteralPath $Context.BootstrapReleaseRoot `
            -Directory `
            -Force
    )
    Assert-BuildDeterminismTest `
        -Condition (
            [string]$First.ReleaseId -ceq [string]$Second.ReleaseId -and
            [string]$First.Root -ceq [string]$Second.Root -and
            $ReleaseDirectories.Count -eq 1 -and
            $FirstCreated -eq $SecondCreated -and
            $FirstSelector -ceq $SecondSelector
        ) `
        -Message 'clean builds did not reuse one immutable Release and selector'
} finally {
    if ([IO.Directory]::Exists($TestRoot)) {
        [IO.Directory]::Delete($TestRoot, $true)
    }
}

Write-Host '[PASS] Windows Bootstrap clean-build determinism' `
    -ForegroundColor Green
