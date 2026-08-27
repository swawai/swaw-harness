[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $skillRoot '..\..\..'))
$lifecycleScript = Join-Path $skillRoot 'scripts\lifecycle.ps1'
$fakeGhswawSource = Join-Path `
    $repositoryRoot `
    '.github\rulesets\tests\fixtures\fake-ghswaw.ps1'
Import-Module `
    (Join-Path $PSScriptRoot 'fixtures\lifecycle-fixture.psm1') `
    -Force
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
            Assert-Contains $text $fragment "$Message; actual error: $text"
        }
        return
    }
    throw "Assertion failed: $Message (no exception was thrown)"
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
    'swaw lifecycle tests ' + [guid]::NewGuid().ToString('N')
)
Initialize-LifecycleFixture -TestRoot $testRoot

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

    $incomplete = New-LifecycleFixture 'incomplete source'
    $missingRelative = '.agents/skills/govern-repository-change/scripts/status.ps1'
    [IO.File]::Delete((Join-Path `
        $incomplete.Root `
        $missingRelative.Replace('/', '\')
    ))
    [void](Invoke-TestGit $incomplete.Root @('add', '-u'))
    [void](Invoke-TestGit $incomplete.Root @(
        'commit', '-m', 'test: remove required source'
    ))
    $incomplete.Head = @(
        Invoke-TestGit $incomplete.Root @('rev-parse', 'HEAD')
    )[-1].Trim()
    [void](Invoke-TestGit $incomplete.Root @(
        'update-ref', 'refs/remotes/origin/main', $incomplete.Head
    ))
    Set-FakeContext $incomplete
    $incompletePlan = & $lifecycleScript plan-install `
        -RepositoryRoot $incomplete.Root
    Assert-Equal $true $incompletePlan.Blocked `
        'incomplete default source blocks activation'
    Assert-Equal 'partial' $incompletePlan.DefaultSourceState `
        'missing required source is reported'
    Assert-True ($incompletePlan.DefaultSourceDiagnostics -ccontains (
        "file:$missingRelative"
    )) 'missing source diagnostic names the exact path'

    $happy = New-LifecycleFixture 'happy path'
    Set-FakeContext $happy
    $status = & $lifecycleScript status -RepositoryRoot $happy.Root
    Assert-Equal 'source_only' $status.OverallState 'source-only status'
    Assert-Equal 'observed' $status.Outcome 'status outcome'
    $plan = & $lifecycleScript plan-install -RepositoryRoot $happy.Root
    Assert-Equal 'create' $plan.Outcome 'install plan'
    Assert-Equal 0 @(Get-FakeCalls $happy 'mutate:').Count 'plan is read-only'
    $created = & $lifecycleScript install `
        -RepositoryRoot $happy.Root `
        -Confirm:$false
    Assert-Equal 'active' $created.RulesetState 'install verification'
    $again = & $lifecycleScript install `
        -RepositoryRoot $happy.Root `
        -Confirm:$false
    Assert-Equal 'none' $again.Outcome 'idempotent install'
    $blockedDelete = & $lifecycleScript uninstall `
        -RepositoryRoot $happy.Root `
        -Confirm:$false
    Assert-Equal $true $blockedDelete.Blocked 'active uninstall is blocked'
    $disabled = & $lifecycleScript disable `
        -RepositoryRoot $happy.Root `
        -Confirm:$false
    Assert-Equal 'disabled' $disabled.RulesetState 'disable verification'
    $deleted = & $lifecycleScript uninstall `
        -RepositoryRoot $happy.Root `
        -Confirm:$false
    Assert-Equal 'absent' $deleted.RulesetState 'uninstall verification'
    Assert-Equal 'source_removal_pending' $deleted.OverallState `
        'uninstall reports pending source removal'
    Assert-True ($deleted.SourceDisposition.RemoveFiles -ccontains (
        '.github/workflows/change-policy.yml'
    )) 'uninstall reports owned source'
    Assert-True ($deleted.SourceDisposition.RemoveFiles -cnotcontains (
        '.github/workflows/validate.yml'
    )) 'uninstall excludes product workflow'
    Assert-True ($deleted.SourceDisposition.RetainFiles -ccontains (
        '.github/rulesets/scripts/protect-main.ps1'
    )) 'uninstall explicitly retains product manager'
    Assert-True ($deleted.SourceDisposition.RemoveFiles -cnotcontains (
        '.github/rulesets/protect-main.json'
    )) 'uninstall excludes product Ruleset declaration'
    Assert-True ($deleted.SourceDisposition.RemoveFiles -cnotcontains (
        '.github/unrelated-owner-note.txt'
    )) 'uninstall excludes unrelated GitHub content'
    $rootManagedBlock = @(
        $deleted.SourceDisposition.RemoveManagedBlocks | Where-Object {
            $_.Path -ceq 'AGENTS.md'
        }
    )[0]
    Assert-Equal '<!-- swaw.repository-change-governance:begin -->' (
        $rootManagedBlock.Begin
    ) 'uninstall reports the exact root block begin marker'
    Assert-Equal '<!-- swaw.repository-change-governance:end -->' (
        $rootManagedBlock.End
    ) 'uninstall reports the exact root block end marker'
    $removalPlan = & $lifecycleScript plan-uninstall `
        -RepositoryRoot $happy.Root
    Assert-Equal 'source_removal_pending' $removalPlan.OverallState `
        'plan-uninstall preserves source-removal intent after remote deletion'
    Assert-Equal "name: product sentinel`n" (
        [IO.File]::ReadAllText($happy.ProductSentinel, [Text.Encoding]::UTF8)
    ) 'product workflow remains byte-for-byte unchanged'
    Assert-Equal $happy.ProductRulesetSnapshot (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($happy.ProductRuleset))
    ) 'product Ruleset declaration remains byte-for-byte unchanged'
    Assert-Equal $happy.UnrelatedFileSnapshot (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($happy.UnrelatedFile))
    ) 'unrelated GitHub content remains byte-for-byte unchanged'

    $staleProduct = New-LifecycleFixture 'stale product governance checks'
    Set-RemoteRuleset $staleProduct {
        param($document)
        $document.enforcement = 'disabled'
    }
    Set-RemoteProductRuleset $staleProduct {
        param($document)
        $document.rules = @($document.rules) + @(
            [pscustomobject][ordered]@{
                type = 'required_status_checks'
                parameters = [pscustomobject][ordered]@{
                    do_not_enforce_on_create = $false
                    required_status_checks = @(
                        [pscustomobject][ordered]@{
                            context = 'Change policy'
                            integration_id = 15368
                        }
                    )
                    strict_required_status_checks_policy = $true
                }
            }
        )
    }
    Set-FakeContext $staleProduct
    $staleProductPlan = & $lifecycleScript plan-uninstall `
        -RepositoryRoot $staleProduct.Root
    Assert-Equal 'drift' $staleProductPlan.ProductRulesetState `
        'uninstall reports stale product governance checks'
    Assert-Equal $true $staleProductPlan.Blocked `
        'stale product governance checks block uninstall'
    Assert-Contains `
        -Text $staleProductPlan.NextAction `
        -Fragment 'protect-main without governance checks' `
        -Message 'uninstall explains the safe migration order'
    [void](& $lifecycleScript uninstall `
        -RepositoryRoot $staleProduct.Root `
        -Confirm:$false)
    Assert-Equal 0 @(Get-FakeCalls $staleProduct 'mutate:DELETE').Count `
        'blocked uninstall never deletes the governance Ruleset'

    $productRace = New-LifecycleFixture 'product drift before delete'
    Set-RemoteRuleset $productRace {
        param($document)
        $document.enforcement = 'disabled'
    }
    Set-FakeContext $productRace 'product-drift-before-delete'
    Assert-Throws {
        & $lifecycleScript uninstall `
            -RepositoryRoot $productRace.Root `
            -Confirm:$false
    } @('protect-main changed after uninstall planning', 'No governance') `
        'cross-Ruleset pre-delete race'
    Assert-Equal 0 @(Get-FakeCalls $productRace 'mutate:DELETE').Count `
        'product race prevents governance deletion'

    $postDeleteRace = New-LifecycleFixture 'product drift after delete'
    Set-RemoteRuleset $postDeleteRace {
        param($document)
        $document.enforcement = 'disabled'
    }
    Set-FakeContext $postDeleteRace 'product-drift-after-delete'
    Assert-Throws {
        & $lifecycleScript uninstall `
            -RepositoryRoot $postDeleteRace.Root `
            -Confirm:$false
    } @(
        'governance Ruleset was deleted and verified absent',
        'Do not remove governance source'
    ) 'cross-Ruleset post-delete race'
    Assert-Equal 1 @(Get-FakeCalls $postDeleteRace 'mutate:DELETE').Count `
        'post-delete race reports the completed governance deletion'
    Assert-Equal $false ([IO.File]::Exists($postDeleteRace.State)) `
        'post-delete race leaves the governance Ruleset absent'

    foreach ($enforcement in @('disabled', 'evaluate')) {
        $invalidDesired = New-LifecycleFixture "desired $enforcement"
        $invalidDocument = Get-Content `
            -LiteralPath $invalidDesired.Ruleset `
            -Raw | ConvertFrom-Json
        $invalidDocument.enforcement = $enforcement
        Write-Utf8 `
            -Path $invalidDesired.Ruleset `
            -Content ($invalidDocument | ConvertTo-Json -Depth 100)
        Set-FakeContext $invalidDesired
        $invalidPlan = & $lifecycleScript plan-install `
            -RepositoryRoot $invalidDesired.Root
        Assert-Equal $true $invalidPlan.Blocked `
            "$enforcement desired enforcement blocks installation"
        Assert-Equal 'unknown' $invalidPlan.RulesetState `
            "$enforcement desired enforcement is not a lifecycle state"
        Assert-Contains `
            -Text $invalidPlan.Diagnostic `
            -Fragment 'active desired enforcement' `
            -Message "$enforcement desired enforcement diagnostic"
        Assert-Equal 0 @(Get-FakeCalls $invalidDesired 'mutate:').Count `
            "$enforcement desired enforcement is read-only"
    }

    $sibling = New-LifecycleFixture 'reserved sibling'
    Set-RemoteRuleset $sibling {
        param($m)
        $m.name = 'swaw-change-governance--00000000000000000000000000000000'
    }
    Set-FakeContext $sibling
    $siblingPlan = & $lifecycleScript plan-install `
        -RepositoryRoot $sibling.Root
    Assert-Equal 'collision' $siblingPlan.RulesetState `
        'stale token identity is reported as a collision'
    Assert-Equal $true $siblingPlan.Blocked `
        'stale token identity blocks installation'
    Assert-Contains `
        -Text $siblingPlan.Diagnostic `
        -Fragment 'sibling identities' `
        -Message 'stale token recovery diagnostic'
    Assert-Equal 0 @(Get-FakeCalls $sibling 'mutate:').Count `
        'stale token identity is never adopted or overwritten'

    $isolated = New-LifecycleFixture 'unrelated remote Ruleset'
    Set-RemoteRuleset $isolated { param($m) $m.name = 'user-owned-main-policy' }
    $unrelatedRemoteSnapshot = [Convert]::ToBase64String(
        [IO.File]::ReadAllBytes($isolated.State)
    )
    Set-FakeContext $isolated
    $isolatedInstall = & $lifecycleScript install `
        -RepositoryRoot $isolated.Root `
        -Confirm:$false
    Assert-Equal 88 $isolatedInstall.RulesetId `
        'create follows the ID returned for the dedicated Ruleset'
    $isolatedDisable = & $lifecycleScript disable `
        -RepositoryRoot $isolated.Root `
        -Confirm:$false
    Assert-Equal 88 $isolatedDisable.RulesetId `
        'disable targets the discovered dedicated Ruleset ID'
    [void](& $lifecycleScript uninstall `
        -RepositoryRoot $isolated.Root `
        -Confirm:$false)
    Assert-Equal 1 @(Get-FakeCalls $isolated (
        'api:PUT:repos/swawai/offline-fixture/rulesets/88'
    )).Count 'disable uses the dedicated Ruleset endpoint'
    Assert-Equal 1 @(Get-FakeCalls $isolated (
        'api:DELETE:repos/swawai/offline-fixture/rulesets/88'
    )).Count 'uninstall uses the dedicated Ruleset endpoint'
    Assert-Equal 0 @(Get-FakeCalls $isolated (
        'api:PUT:repos/swawai/offline-fixture/rulesets/77'
    )).Count 'lifecycle never updates the unrelated Ruleset'
    Assert-Equal 0 @(Get-FakeCalls $isolated (
        'api:DELETE:repos/swawai/offline-fixture/rulesets/77'
    )).Count 'lifecycle never deletes the unrelated Ruleset'
    Assert-Equal $unrelatedRemoteSnapshot (
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($isolated.State))
    ) 'unrelated remote Ruleset remains byte-for-byte unchanged'
    Assert-Equal $false ([IO.File]::Exists($isolated.OtherState)) `
        'dedicated remote Ruleset is deleted'

    $legacy = New-LifecycleFixture 'exact legacy governance projection'
    Set-RemoteLegacyRuleset $legacy
    Set-FakeContext $legacy
    $legacyStatus = & $lifecycleScript status -RepositoryRoot $legacy.Root
    Assert-Equal 'legacy_active' $legacyStatus.RulesetState `
        'status recognizes only the exact active predecessor'
    Assert-Equal 'migration_required' $legacyStatus.OverallState `
        'status exposes the bounded predecessor migration'
    $legacyPlan = & $lifecycleScript plan-install -RepositoryRoot $legacy.Root
    Assert-Equal 'migrate' $legacyPlan.Outcome `
        'plan-install exposes the bounded legacy migration'
    Assert-Equal 0 @(Get-FakeCalls $legacy 'mutate:').Count `
        'legacy migration planning is read-only'
    $migrated = & $lifecycleScript install `
        -RepositoryRoot $legacy.Root `
        -Confirm:$false
    Assert-Equal 'active' $migrated.RulesetState `
        'legacy migration verifies the slim active Ruleset'
    Assert-Equal 1 @(Get-FakeCalls $legacy 'mutate:PUT').Count `
        'legacy migration updates only its exact Ruleset ID once'

    $legacyRace = New-LifecycleFixture 'legacy projection race'
    Set-RemoteLegacyRuleset $legacyRace
    Set-FakeContext $legacyRace 'drift-before-mutation'
    Assert-Throws {
        & $lifecycleScript install `
            -RepositoryRoot $legacyRace.Root `
            -Confirm:$false
    } @('changed after planning', 'No mutation was attempted') `
        'legacy migration TOCTOU guard'
    Assert-Equal 0 @(Get-FakeCalls $legacyRace 'mutate:').Count `
        'legacy migration race never writes'

    $drift = New-LifecycleFixture 'drift'
    Set-RemoteRuleset $drift { param($m) $m.target = 'tag' }
    Set-FakeContext $drift
    $drifted = & $lifecycleScript install `
        -RepositoryRoot $drift.Root `
        -Confirm:$false
    Assert-Equal $true $drifted.Blocked 'drift blocks install'
    Assert-Equal 0 @(Get-FakeCalls $drift 'mutate:').Count 'drift is not reconciled'

    $changed = New-LifecycleFixture 'changed after plan'
    Set-RemoteRuleset $changed $null
    Set-FakeContext $changed 'drift-before-mutation'
    Assert-Throws {
        & $lifecycleScript disable `
            -RepositoryRoot $changed.Root `
            -Confirm:$false
    } @('changed after planning', 'No mutation was attempted') `
        'pre-mutation drift'
    Assert-Equal 0 @(Get-FakeCalls $changed 'mutate:').Count `
        'TOCTOU guard prevents mutation'

    $lost = New-LifecycleFixture 'response lost'
    Set-FakeContext $lost 'mutation-applied-unknown'
    Assert-Throws {
        & $lifecycleScript install `
            -RepositoryRoot $lost.Root `
            -Confirm:$false
    } @('result is unknown', 'Do not retry automatically') 'lost response'
    Set-FakeContext $lost
    $recovered = & $lifecycleScript status -RepositoryRoot $lost.Root
    Assert-Equal 'active' $recovered.RulesetState 'status recovers applied write'
    Assert-Equal 1 @(Get-FakeCalls $lost 'mutate:POST').Count `
        'recovery does not replay write'

    $lostDisable = New-LifecycleFixture 'disable response lost'
    Set-RemoteRuleset $lostDisable $null
    Set-FakeContext $lostDisable 'mutation-applied-unknown'
    Assert-Throws {
        & $lifecycleScript disable `
            -RepositoryRoot $lostDisable.Root `
            -Confirm:$false
    } @('result is unknown', 'Do not retry automatically') `
        'lost disable response'
    Set-FakeContext $lostDisable
    $disableRecovery = & $lifecycleScript status `
        -RepositoryRoot $lostDisable.Root
    Assert-Equal 'disabled' $disableRecovery.RulesetState `
        'status recovers applied disable'
    Assert-Equal 1 @(Get-FakeCalls $lostDisable 'mutate:PUT').Count `
        'recovery does not replay disable'

    $lostDelete = New-LifecycleFixture 'delete response lost'
    Set-RemoteRuleset $lostDelete {
        param($m)
        $m.enforcement = 'disabled'
    }
    Set-FakeContext $lostDelete 'delete-applied-unknown'
    Assert-Throws {
        & $lifecycleScript uninstall `
            -RepositoryRoot $lostDelete.Root `
            -Confirm:$false
    } @('result is unknown', 'Do not retry automatically') `
        'lost delete response'
    Set-FakeContext $lostDelete
    $deleteRecovery = & $lifecycleScript status `
        -RepositoryRoot $lostDelete.Root
    Assert-Equal 'absent' $deleteRecovery.RulesetState `
        'status recovers applied delete'

    Write-Output (
        "PASS: $assertionCount assertions; lifecycle mutations and recovery " +
        'were simulated offline.'
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
            'swaw lifecycle tests '
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
