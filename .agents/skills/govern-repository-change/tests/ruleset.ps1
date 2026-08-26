[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $skillRoot '..\..\..'))
$rulesetScript = Join-Path $skillRoot 'scripts\ruleset.ps1'
$desiredSource = Join-Path `
    $repositoryRoot `
    '.github\rulesets\protect-main.json'
$fakeGhswawSource = Join-Path $PSScriptRoot 'fixtures\fake-ghswaw.ps1'
$git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$assertionCount = 0
function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:assertionCount++
}
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
            Assert-Contains `
                -Text $text `
                -Fragment $fragment `
                -Message "$Message; actual error: $text"
        }
        return $text
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
function New-TestFixture {
    param([string]$Name)

    $root = Join-Path $script:testRoot $Name
    $stateRoot = Join-Path $script:testRoot "state-$Name"
    $rulesetRoot = Join-Path $root '.github\rulesets'
    [void][IO.Directory]::CreateDirectory($rulesetRoot)
    [void][IO.Directory]::CreateDirectory($stateRoot)
    [void](Invoke-TestGit $root @('init', '--initial-branch=main'))
    [void](Invoke-TestGit $root @('config', 'user.name', 'Offline Test'))
    [void](Invoke-TestGit $root @(
        'config', 'user.email', 'offline@example.invalid'
    ))
    [IO.File]::Copy(
        $script:desiredSource,
        (Join-Path $rulesetRoot 'protect-main.json'),
        $true
    )
    [IO.File]::WriteAllText((Join-Path $root 'seed.txt'), 'seed')
    [void](Invoke-TestGit $root @('add', '.'))
    [void](Invoke-TestGit $root @('commit', '-m', 'test: seed fixture'))
    [void](Invoke-TestGit $root @(
        'remote', 'add', 'origin',
        'https://github.com/swawai/offline-fixture.git'
    ))
    return [pscustomobject]@{
        Root = $root
        Log = Join-Path $stateRoot 'fake-ghswaw.log'
        State = Join-Path $stateRoot 'remote-ruleset.json'
        Ruleset = Join-Path $rulesetRoot 'protect-main.json'
    }
}
function Set-FakeContext {
    param($Fixture, [string]$Scenario = 'happy')
    $env:RULESET_FAKE_SCENARIO = $Scenario
    $env:RULESET_FAKE_LOG = $Fixture.Log
    $env:RULESET_FAKE_STATE = $Fixture.State
}
function Set-RemoteRuleset {
    param($Fixture, [scriptblock]$Transform)

    $document = Get-Content -LiteralPath $Fixture.Ruleset -Raw |
        ConvertFrom-Json
    if ($null -ne $Transform) {
        & $Transform $document
    }
    [IO.File]::WriteAllText(
        $Fixture.State,
        ($document | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
}
function Get-FakeCalls {
    param($Fixture)
    if (-not [IO.File]::Exists($Fixture.Log)) { return @() }
    return @([IO.File]::ReadAllLines($Fixture.Log) | Where-Object { $_ })
}

function Assert-CallCount {
    param($Fixture, [string]$Prefix, [int]$Expected)
    $actual = @(Get-FakeCalls $Fixture | Where-Object {
        $_.StartsWith($Prefix, [StringComparison]::Ordinal)
    }).Count
    Assert-Equal $Expected $actual "call count for $Prefix"
}

$originalPath = $env:PATH
$savedEnvironment = @{}
foreach ($name in @(
    'RULESET_FAKE_SCENARIO',
    'RULESET_FAKE_LOG',
    'RULESET_FAKE_STATE'
)) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable(
        $name,
        'Process'
    )
}
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path `
    $tempParent `
    ('swaw-ruleset-tests-' + [guid]::NewGuid().ToString('N'))

try {
    [void][IO.Directory]::CreateDirectory($testRoot)
    $fakeBin = Join-Path $testRoot 'bin'
    [void][IO.Directory]::CreateDirectory($fakeBin)
    $fakeScript = Join-Path $fakeBin 'fake-ghswaw.ps1'
    [IO.File]::Copy($fakeGhswawSource, $fakeScript, $true)
    [IO.File]::WriteAllText(
        (Join-Path $fakeBin 'ghswaw.cmd'),
        "@echo off`r`npowershell.exe -NoLogo -NoProfile -NonInteractive " +
            "-ExecutionPolicy Bypass -File `"%~dp0fake-ghswaw.ps1`" %*`r`n" +
            "exit /b %ERRORLEVEL%`r`n",
        [Text.ASCIIEncoding]::new()
    )
    $env:PATH = $fakeBin + [IO.Path]::PathSeparator + $originalPath

    $absent = New-TestFixture 'absent'
    Set-FakeContext $absent
    $status = & $rulesetScript status -RepositoryRoot $absent.Root
    Assert-Equal 'absent' $status.State 'absent status'
    Assert-Equal 'observed' $status.Outcome 'status outcome'
    Assert-CallCount $absent 'mutate:' 0
    $plan = & $rulesetScript plan -RepositoryRoot $absent.Root
    Assert-Equal 'create' $plan.Outcome 'absent plan'
    Assert-CallCount $absent 'mutate:' 0

    $mixedStatus = & $rulesetScript Status -RepositoryRoot $absent.Root
    Assert-Equal 'status' $mixedStatus.Mode 'mixed-case status normalization'
    $mixedPlan = & $rulesetScript PLAN -RepositoryRoot $absent.Root
    Assert-Equal 'plan' $mixedPlan.Mode 'mixed-case plan normalization'
    Assert-CallCount $absent 'mutate:' 0

    $created = & $rulesetScript apply -RepositoryRoot $absent.Root
    Assert-Equal 'create' $created.Outcome 'create outcome'
    Assert-Equal 'in_sync' $created.State 'create verification'
    Assert-CallCount $absent 'mutate:POST' 1
    $unchanged = & $rulesetScript apply -RepositoryRoot $absent.Root
    Assert-Equal 'none' $unchanged.Outcome 'idempotent apply'
    Assert-CallCount $absent 'mutate:' 1

    $drift = New-TestFixture 'drift'
    Set-RemoteRuleset $drift { param($document) $document.enforcement = 'disabled' }
    Set-FakeContext $drift
    $driftPlan = & $rulesetScript plan -RepositoryRoot $drift.Root
    Assert-Equal 'drift' $driftPlan.State 'drift state'
    Assert-Equal 'update' $driftPlan.Outcome 'drift plan'
    Assert-CallCount $drift 'mutate:' 0
    $updated = & $rulesetScript apply -RepositoryRoot $drift.Root
    Assert-Equal 'update' $updated.Outcome 'update outcome'
    Assert-Equal 'in_sync' $updated.State 'update verification'
    Assert-CallCount $drift 'mutate:PUT' 1

    $reordered = New-TestFixture 'reordered'
    Set-RemoteRuleset $reordered {
        param($document)
        [array]::Reverse($document.rules)
    }
    Set-FakeContext $reordered
    $reorderedStatus = & $rulesetScript status -RepositoryRoot $reordered.Root
    Assert-Equal 'in_sync' $reorderedStatus.State 'set-like array comparison'

    $secondPage = New-TestFixture 'second-page'
    Set-RemoteRuleset $secondPage $null
    Set-FakeContext $secondPage 'second-page'
    $secondPageStatus = & $rulesetScript status -RepositoryRoot $secondPage.Root
    Assert-Equal 'in_sync' $secondPageStatus.State 'second-page Ruleset discovery'
    Assert-CallCount $secondPage 'list-page:' 2

    $whatIf = New-TestFixture 'whatif'
    Set-FakeContext $whatIf
    $whatIfResult = & $rulesetScript apply `
        -RepositoryRoot $whatIf.Root `
        -WhatIf
    Assert-Equal 'create' $whatIfResult.Outcome 'WhatIf outcome'
    Assert-Equal $false ([IO.File]::Exists($whatIf.State)) 'WhatIf remote state'
    Assert-CallCount $whatIf 'mutate:' 0

    $duplicate = New-TestFixture 'duplicate'
    Set-FakeContext $duplicate 'duplicate'
    [void](Assert-Throws {
        & $rulesetScript status -RepositoryRoot $duplicate.Root
    } @('multiple Rulesets', 'protect-main') 'duplicate Ruleset names')
    Assert-CallCount $duplicate 'mutate:' 0

    $inherited = New-TestFixture 'inherited'
    Set-FakeContext $inherited 'inherited'
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $inherited.Root
    } @(
        'not owned by repository',
        "source_type='Organization'"
    ) 'inherited Ruleset ownership')
    Assert-CallCount $inherited 'mutate:' 0

    $wrongSummarySource = New-TestFixture 'wrong-summary-source'
    Set-FakeContext $wrongSummarySource 'wrong-summary-source'
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $wrongSummarySource.Root
    } @(
        'not owned by repository',
        "source='other/repository'"
    ) 'Ruleset summary source ownership')
    Assert-CallCount $wrongSummarySource 'mutate:' 0

    $wrongDetailOwner = New-TestFixture 'wrong-detail-owner'
    Set-RemoteRuleset $wrongDetailOwner $null
    Set-FakeContext $wrongDetailOwner 'wrong-detail-owner'
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $wrongDetailOwner.Root
    } @(
        'not owned by repository',
        "source_type='Organization'"
    ) 'Ruleset detail ownership')
    Assert-CallCount $wrongDetailOwner 'mutate:' 0

    $readFailure = New-TestFixture 'read-failure'
    Set-FakeContext $readFailure 'read-failure'
    [void](Assert-Throws {
        & $rulesetScript plan -RepositoryRoot $readFailure.Root
    } @('List GitHub Rulesets page 1 failed') 'read failure')
    Assert-CallCount $readFailure 'mutate:' 0

    $uncertain = New-TestFixture 'mutation-unknown'
    Set-FakeContext $uncertain 'mutation-unknown'
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $uncertain.Root
    } @(
        'result is unknown',
        'Do not retry automatically',
        'ruleset.ps1 status'
    ) 'uncertain mutation result')
    Assert-CallCount $uncertain 'mutate:POST' 1

    $verificationFailure = New-TestFixture 'verification-failure'
    Set-FakeContext $verificationFailure 'verification-failure'
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $verificationFailure.Root
    } @(
        'verification result is unknown',
        'Do not retry automatically',
        'ruleset.ps1 status'
    ) 'post-write verification failure')
    Assert-CallCount $verificationFailure 'mutate:POST' 1

    $wrongOrigin = New-TestFixture 'wrong-origin'
    [void](Invoke-TestGit $wrongOrigin.Root @(
        'remote', 'set-url', 'origin',
        'https://gitlab.com/swawai/offline-fixture.git'
    ))
    Set-FakeContext $wrongOrigin
    [void](Assert-Throws {
        & $rulesetScript status -RepositoryRoot $wrongOrigin.Root
    } @('not an explicit github.com repository URL') 'origin authority')
    Assert-CallCount $wrongOrigin 'doctor' 0

    $invalid = New-TestFixture 'invalid-local'
    $invalidDocument = Get-Content -LiteralPath $invalid.Ruleset -Raw |
        ConvertFrom-Json
    $invalidDocument | Add-Member -NotePropertyName id -NotePropertyValue 77
    [IO.File]::WriteAllText(
        $invalid.Ruleset,
        ($invalidDocument | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
    Set-FakeContext $invalid
    [void](Assert-Throws {
        & $rulesetScript plan -RepositoryRoot $invalid.Root
    } @("unsupported top-level property 'id'") 'API payload contract')
    Assert-CallCount $invalid 'doctor' 0

    $invalidCase = New-TestFixture 'invalid-enum-case'
    $invalidCaseDocument = Get-Content -LiteralPath $invalidCase.Ruleset -Raw |
        ConvertFrom-Json
    $invalidCaseDocument.target = 'Branch'
    [IO.File]::WriteAllText(
        $invalidCase.Ruleset,
        ($invalidCaseDocument | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
    Set-FakeContext $invalidCase
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $invalidCase.Root
    } @("Ruleset property 'target' is invalid") 'case-sensitive Ruleset enum')
    Assert-CallCount $invalidCase 'doctor' 0

    $renamed = New-TestFixture 'renamed-local'
    $renamedDocument = Get-Content -LiteralPath $renamed.Ruleset -Raw |
        ConvertFrom-Json
    $renamedDocument.name = 'protect-primary'
    [IO.File]::WriteAllText(
        $renamed.Ruleset,
        ($renamedDocument | ConvertTo-Json -Depth 100),
        [Text.UTF8Encoding]::new($false)
    )
    Set-FakeContext $renamed
    [void](Assert-Throws {
        & $rulesetScript apply -RepositoryRoot $renamed.Root
    } @(
        'stable remote identity',
        "must remain 'protect-main'"
    ) 'Ruleset identity rename guard')
    Assert-CallCount $renamed 'doctor' 0

    Write-Output (
        "PASS: $assertionCount assertions; all Ruleset behavior was " +
        'simulated offline.'
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
    if ($resolvedRoot.StartsWith(
        $expectedPrefix,
        [StringComparison]::OrdinalIgnoreCase
    ) -and [IO.Path]::GetFileName($resolvedRoot).StartsWith(
        'swaw-ruleset-tests-'
    )) {
        if ([IO.Directory]::Exists($resolvedRoot)) {
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
}
