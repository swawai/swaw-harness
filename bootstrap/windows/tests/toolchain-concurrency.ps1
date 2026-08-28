[CmdletBinding()]
param([string]$RepositoryDataRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Assert-ToolchainConcurrencyTest {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Toolchain concurrency test failed: $Message"
    }
}

$WindowsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $WindowsRoot '..\..'))
. (Join-Path $WindowsRoot 'builder\context.ps1')
. (Join-Path $WindowsRoot 'builder\contract.ps1')
. (Join-Path $WindowsRoot 'toolchain\lifecycle.ps1')
. (Join-Path $PSScriptRoot 'paths.ps1')

$RepositoryDataRoot = Resolve-SwawHarnessWindowsTestRepositoryDataRoot `
    -RepositoryDataRoot $RepositoryDataRoot `
    -RepositoryRoot $RepositoryRoot
$SetupPath = Join-Path $WindowsRoot 'toolchain-setup.ps1'
$Jobs = @(1..2 | ForEach-Object {
    Start-Job -ScriptBlock {
        param($ScriptPath, $Root)

        $Output = @(& pwsh `
            -NoLogo `
            -NoProfile `
            -File $ScriptPath `
            -RepositoryDataRoot $Root `
            2>&1)
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = [string]::Join("`n", [string[]]$Output)
        }
    } -ArgumentList $SetupPath, $RepositoryDataRoot
})
try {
    [void](Wait-Job -Job $Jobs -Timeout 1800)
    $Results = @($Jobs | Receive-Job -ErrorAction Stop)
    Assert-ToolchainConcurrencyTest `
        -Condition (
            $Results.Count -eq 2 -and
            @($Results | Where-Object { $_.ExitCode -ne 0 }).Count -eq 0
        ) `
        -Message (
            'concurrent setup process failed: ' +
            [string]::Join(' | ', [string[]]@($Results.Output))
        )

    $Context = New-SwawHarnessWindowsBootstrapContext -RepositoryDataRoot $RepositoryDataRoot
    $Contract = Read-SwawHarnessWindowsBootstrapContract `
        -Path (Join-Path $WindowsRoot 'contract.json')
    $ToolchainId = Get-SwawHarnessToolchainId -Contract $Contract
    $MatchingRoots = @(Get-ChildItem `
        -LiteralPath $Context.ToolchainRoot `
        -Directory `
        -Force | Where-Object {
            $MetadataPath = Join-Path $_.FullName 'toolchain.json'
            if (-not [IO.File]::Exists($MetadataPath)) {
                return $false
            }
            try {
                $Metadata = Read-SwawHarnessJsonFile `
                    -Path $MetadataPath `
                    -Description 'concurrent toolchain metadata' `
                    -MaximumBytes 32MB
                return [string]$Metadata.toolchainId -ceq $ToolchainId
            } catch {
                return $false
            }
        })
    Assert-ToolchainConcurrencyTest `
        -Condition (
            $MatchingRoots.Count -eq 1 -and
            $null -ne (Get-SwawHarnessValidToolchain `
                -Context $Context `
                -Contract $Contract `
                -InstallRoot $MatchingRoots[0].FullName)
        ) `
        -Message 'concurrent setup did not converge on one valid complete ID'

    Write-Host '[PASS] Windows Bootstrap concurrent toolchain setup' `
        -ForegroundColor Green
} finally {
    $Jobs | Remove-Job -Force -ErrorAction SilentlyContinue
}
