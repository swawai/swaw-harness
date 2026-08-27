[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $skillRoot '..\..\..'))
$manifestSource = Join-Path $skillRoot 'ownership.json'
$fakeGhswawSource = Join-Path `
    $repositoryRoot `
    '.github\rulesets\tests\fixtures\fake-ghswaw.ps1'
$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$assertionCount = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) {
        throw "Assertion failed: $Message (expected '$Expected', actual '$Actual')"
    }
    $script:assertionCount++
}

function Assert-Contains {
    param([string]$Text, [string]$Fragment, [string]$Message)
    if (-not $Text.Contains($Fragment)) {
        throw "Assertion failed: $Message (missing '$Fragment')"
    }
    $script:assertionCount++
}

function Assert-Throws {
    param([scriptblock]$Action, [string[]]$Fragments, [string]$Message)
    try { & $Action | Out-Null }
    catch {
        $text = $_.Exception.Message
        foreach ($fragment in $Fragments) {
            Assert-Contains $text $fragment "$Message; actual error: $text"
        }
        return
    }
    throw "Assertion failed: $Message (no exception was thrown)"
}

function Invoke-TestGit {
    param([string]$Root, [string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = @(& $script:git.Source -C $Root @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($exitCode -ne 0) {
        throw "Fixture git failed: $($output -join [Environment]::NewLine)"
    }
    return $output
}

function Write-Utf8 {
    param([string]$Path, [string]$Content)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Copy-FixtureFile {
    param([string]$Root, [string]$RelativePath)
    $source = Join-Path $script:repositoryRoot $RelativePath.Replace('/', '\')
    $target = Join-Path $Root $RelativePath.Replace('/', '\')
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy($source, $target, $true)
}

function Get-FileBytes {
    param([string]$Path)
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

function New-MigrationFixture {
    param([string]$Name)

    $root = Join-Path $script:testRoot $Name
    $stateRoot = Join-Path $script:testRoot "state-$Name"
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory($stateRoot)
    [void](Invoke-TestGit $root @('init', '--initial-branch=main'))
    [void](Invoke-TestGit $root @('config', 'user.name', 'Offline Test'))
    [void](Invoke-TestGit $root @(
        'config', 'user.email', 'offline@example.invalid'
    ))

    $manifest = Get-Content -LiteralPath $script:manifestSource -Raw |
        ConvertFrom-Json
    foreach ($path in @(
        @($manifest.versioned.required_files) +
        @($manifest.versioned.retained_files) +
        @($manifest.versioned.removable_files)
    ) | Sort-Object -Unique) {
        Copy-FixtureFile $root ([string]$path)
    }
    foreach ($block in @($manifest.versioned.managed_blocks)) {
        Copy-FixtureFile $root ([string]$block.path)
    }
    Copy-FixtureFile $root '.github/rulesets/protect-main.json'

    [void](Invoke-TestGit $root @('add', '.'))
    [void](Invoke-TestGit $root @('commit', '-m', 'test: seed migration'))
    [void](Invoke-TestGit $root @(
        'remote', 'add', 'origin',
        'https://github.com/swawai/offline-fixture.git'
    ))
    $head = @(Invoke-TestGit $root @('rev-parse', 'HEAD'))[-1].Trim()
    [void](Invoke-TestGit $root @(
        'update-ref', 'refs/remotes/origin/main', $head
    ))

    return [pscustomobject]@{
        Root = $root
        Head = $head
        Log = Join-Path $stateRoot 'fake-ghswaw.log'
        ProductState = Join-Path $stateRoot 'protect-main.remote.json'
        GovernanceState = Join-Path $stateRoot 'governance.remote.json'
        ProductDesired = Join-Path $root '.github\rulesets\protect-main.json'
        GovernanceDesired = Join-Path `
            $root `
            '.github\rulesets\swaw-change-governance.json'
        Script = Join-Path `
            $root `
            '.github\rulesets\scripts\protect-main.ps1'
    }
}

function Set-FakeContext {
    param($Fixture)
    $env:RULESET_FAKE_SCENARIO = 'happy'
    $env:RULESET_FAKE_LOG = $Fixture.Log
    $env:RULESET_FAKE_STATE = $Fixture.ProductState
    $env:RULESET_FAKE_OTHER_STATE = $Fixture.GovernanceState
    $env:RULESET_FAKE_PRODUCT_STATE = ''
    $env:RULESET_FAKE_NAME = 'protect-main'
    $env:RULESET_FAKE_MAIN_OID = $Fixture.Head
}

function Set-RemoteProductBeforeMigration {
    param(
        $Fixture,
        [switch]$LegacyCombined
    )

    $document = Get-Content -LiteralPath $Fixture.ProductDesired -Raw |
        ConvertFrom-Json
    $requiredChecks = @(
        [pscustomobject][ordered]@{
            context = 'Product validation'
            integration_id = 15368
        }
    )
    if ($LegacyCombined) {
        $requiredChecks = @(
            [pscustomobject][ordered]@{
                context = 'Change policy'
                integration_id = 15368
            }
        ) + $requiredChecks
    }
    $document.rules = @($document.rules) + @(
        [pscustomobject][ordered]@{
            type = 'required_status_checks'
            parameters = [pscustomobject][ordered]@{
                do_not_enforce_on_create = $false
                required_status_checks = $requiredChecks
                strict_required_status_checks_policy = $true
            }
        }
    )
    Write-Utf8 $Fixture.ProductState ($document | ConvertTo-Json -Depth 100)
}

function Set-RemoteGovernance {
    param(
        $Fixture,
        [ValidateSet('active', 'disabled', 'drift')][string]$State
    )

    $document = Get-Content -LiteralPath $Fixture.GovernanceDesired -Raw |
        ConvertFrom-Json
    if ($State -ceq 'disabled') { $document.enforcement = 'disabled' }
    elseif ($State -ceq 'drift') { $document.target = 'tag' }
    Write-Utf8 $Fixture.GovernanceState ($document | ConvertTo-Json -Depth 100)
}

function Assert-CallCount {
    param($Fixture, [string]$Prefix, [int]$Expected)
    $calls = @()
    if ([IO.File]::Exists($Fixture.Log)) {
        $calls = @([IO.File]::ReadAllLines($Fixture.Log) | Where-Object {
            $_.StartsWith($Prefix, [StringComparison]::Ordinal)
        })
    }
    Assert-Equal $Expected $calls.Count "call count for $Prefix"
}

$originalPath = $env:PATH
$savedEnvironment = @{}
foreach ($name in @(
    'RULESET_FAKE_SCENARIO', 'RULESET_FAKE_LOG', 'RULESET_FAKE_STATE',
    'RULESET_FAKE_OTHER_STATE', 'RULESET_FAKE_PRODUCT_STATE',
    'RULESET_FAKE_NAME',
    'RULESET_FAKE_MAIN_OID'
)) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable(
        $name,
        'Process'
    )
}
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempParent (
    'swaw-ruleset-migration-tests-' + [guid]::NewGuid().ToString('N')
)

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $fakeBin = Join-Path $testRoot 'bin'
    [void][IO.Directory]::CreateDirectory($fakeBin)
    [IO.File]::Copy(
        $fakeGhswawSource,
        (Join-Path $fakeBin 'fake-ghswaw.ps1'),
        $true
    )
    Write-Utf8 (Join-Path $fakeBin 'ghswaw.cmd') (
        "@echo off`r`npowershell.exe -NoLogo -NoProfile -NonInteractive " +
        "-ExecutionPolicy Bypass -File `"%~dp0fake-ghswaw.ps1`" %*`r`n" +
        "exit /b %ERRORLEVEL%`r`n"
    )
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $originalPath

    foreach ($blockedState in @('absent', 'disabled', 'drift')) {
        $fixture = New-MigrationFixture "blocked-$blockedState"
        Set-RemoteProductBeforeMigration $fixture
        if ($blockedState -cne 'absent') {
            Set-RemoteGovernance $fixture $blockedState
        }
        $productBefore = Get-FileBytes $fixture.ProductState
        Set-FakeContext $fixture
        $status = & $fixture.Script status -RepositoryRoot $fixture.Root
        Assert-Equal $true $status.RequiresGovernanceActivation `
            "Product-only migration reports its governance prerequisite"
        Assert-Throws {
            & $fixture.Script apply `
                -RepositoryRoot $fixture.Root `
                -Confirm:$false
        } @('Activate and verify the dedicated governance Ruleset') `
            "migration blocked while governance is $blockedState"
        Assert-Equal $productBefore (Get-FileBytes $fixture.ProductState) `
            "protect-main remains unchanged while governance is $blockedState"
        Assert-CallCount $fixture 'mutate:' 0
    }

    $ready = New-MigrationFixture 'ready'
    Set-RemoteProductBeforeMigration $ready
    Set-RemoteGovernance $ready 'active'
    $governanceBefore = Get-FileBytes $ready.GovernanceState
    Set-FakeContext $ready
    $result = & $ready.Script apply `
        -RepositoryRoot $ready.Root `
        -Confirm:$false
    Assert-Equal 'update' $result.Outcome 'migration updates protect-main'
    Assert-Equal 'in_sync' $result.State 'protect-main verification'
    Assert-Equal 77 $result.RulesetId 'protect-main routes to ID 77'
    Assert-Equal $governanceBefore (Get-FileBytes $ready.GovernanceState) `
        'dedicated governance ID 88 remains byte-identical'
    Assert-CallCount $ready `
        'api:PUT:repos/swawai/offline-fixture/rulesets/77' 1
    Assert-CallCount $ready `
        'api:PUT:repos/swawai/offline-fixture/rulesets/88' 0
    Assert-CallCount $ready 'mutate:PUT' 1

    $productAfter = Get-Content -LiteralPath $ready.ProductState -Raw |
        ConvertFrom-Json
    $statusRules = @($productAfter.rules | Where-Object {
        $_.type -ceq 'required_status_checks'
    })
    $contexts = @($statusRules | ForEach-Object {
        @($_.parameters.required_status_checks) | ForEach-Object {
            [string]$_.context
        }
    })
    Assert-Equal 0 $statusRules.Count `
        'migrated protect-main contains no required status rule'
    Assert-Equal 0 $contexts.Count `
        'migrated protect-main contains no required status checks'

    $legacy = New-MigrationFixture 'legacy-combined'
    Set-RemoteProductBeforeMigration $legacy -LegacyCombined
    Set-RemoteGovernance $legacy 'active'
    Set-FakeContext $legacy
    $legacyStatus = & $legacy.Script status -RepositoryRoot $legacy.Root
    Assert-Equal $true $legacyStatus.RequiresGovernanceActivation `
        'legacy combined migration reports its governance prerequisite'
    $legacyResult = & $legacy.Script apply `
        -RepositoryRoot $legacy.Root `
        -Confirm:$false
    Assert-Equal 'in_sync' $legacyResult.State `
        'legacy combined migration remains supported'
    Assert-CallCount $legacy 'mutate:PUT' 1

    Write-Output (
        "PASS: $assertionCount assertions; governance activation gates the " +
        'protect-main migration and ID 88 remains untouched.'
    )
}
finally {
    $env:PATH = $originalPath
    foreach ($name in $savedEnvironment.Keys) {
        $value = $savedEnvironment[$name]
        if ($null -eq $value) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        }
        else {
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
    $resolvedRoot = [IO.Path]::GetFullPath($testRoot)
    $expectedPrefix = $tempParent + [IO.Path]::DirectorySeparatorChar
    if ([IO.Directory]::Exists($resolvedRoot) -and
        $resolvedRoot.StartsWith(
            $expectedPrefix,
            [StringComparison]::OrdinalIgnoreCase
        ) -and
        [IO.Path]::GetFileName($resolvedRoot).StartsWith(
            'swaw-ruleset-migration-tests-'
        )) {
        foreach ($file in [IO.Directory]::EnumerateFiles(
            $resolvedRoot,
            '*',
            [IO.SearchOption]::AllDirectories
        )) {
            [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
        }
        [IO.Directory]::Delete($resolvedRoot, $true)
    }
}
