$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\..\..\..'
))
$script:manifestSource = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\ownership.json'
))
$script:git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$script:testRoot = ''

function Initialize-LifecycleFixture {
    param([Parameter(Mandatory = $true)][string]$TestRoot)

    $script:testRoot = [IO.Path]::GetFullPath($TestRoot)
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

function New-LifecycleFixture {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($script:testRoot)) {
        throw 'Initialize-LifecycleFixture must run before creating fixtures.'
    }
    $root = Join-Path $script:testRoot $Name
    $stateRoot = Join-Path $script:testRoot "state-$Name"
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory($stateRoot)
    [void](Invoke-TestGit $root @('init', '--initial-branch=main'))
    [void](Invoke-TestGit $root @('config', 'user.name', 'Offline Test'))
    [void](Invoke-TestGit $root @(
        'config', 'user.email', 'offline@example.invalid'
    ))
    $manifestTarget = Join-Path $root `
        '.agents\skills\govern-repository-change\ownership.json'
    [void][IO.Directory]::CreateDirectory(
        [IO.Path]::GetDirectoryName($manifestTarget)
    )
    [IO.File]::Copy($script:manifestSource, $manifestTarget, $true)
    $manifest = Get-Content -LiteralPath $manifestTarget -Raw |
        ConvertFrom-Json
    foreach ($path in @(
        @($manifest.versioned.required_files) +
        @($manifest.versioned.retained_files) +
        @($manifest.versioned.removable_files)
    )) {
        Copy-FixtureFile $root ([string]$path)
    }
    foreach ($block in @($manifest.versioned.managed_blocks)) {
        Copy-FixtureFile $root ([string]$block.path)
    }
    $productRuleset = Join-Path $root '.github\rulesets\protect-main.json'
    Copy-FixtureFile $root '.github/rulesets/protect-main.json'
    $productSentinel = Join-Path $root '.github\workflows\validate.yml'
    Write-Utf8 $productSentinel "name: product sentinel`n"
    $unrelatedFile = Join-Path $root '.github\unrelated-owner-note.txt'
    Write-Utf8 $unrelatedFile "owned elsewhere`n"
    $productRulesetSnapshot = [Convert]::ToBase64String(
        [IO.File]::ReadAllBytes($productRuleset)
    )
    $productState = Join-Path $stateRoot 'remote-product-ruleset.json'
    [IO.File]::Copy($productRuleset, $productState, $true)
    $unrelatedFileSnapshot = [Convert]::ToBase64String(
        [IO.File]::ReadAllBytes($unrelatedFile)
    )
    [void](Invoke-TestGit $root @('add', '.'))
    [void](Invoke-TestGit $root @('commit', '-m', 'test: seed lifecycle'))
    [void](Invoke-TestGit $root @(
        'remote', 'add', 'origin',
        'https://github.com/swawai/offline-fixture.git'
    ))
    $head = @(
        Invoke-TestGit $root @('rev-parse', 'HEAD')
    )[-1].Trim()
    [void](Invoke-TestGit $root @(
        'update-ref', 'refs/remotes/origin/main', $head
    ))
    return [pscustomobject]@{
        Root = $root
        Head = $head
        Log = Join-Path $stateRoot 'fake-ghswaw.log'
        State = Join-Path $stateRoot 'remote-ruleset.json'
        OtherState = Join-Path $stateRoot 'other-ruleset.json'
        ProductState = $productState
        Ruleset = Join-Path `
            $root `
            '.github\rulesets\swaw-change-governance.json'
        ProductSentinel = $productSentinel
        ProductRuleset = $productRuleset
        ProductRulesetSnapshot = $productRulesetSnapshot
        UnrelatedFile = $unrelatedFile
        UnrelatedFileSnapshot = $unrelatedFileSnapshot
    }
}

function Set-FakeContext {
    param($Fixture, [string]$Scenario = 'happy')

    $env:RULESET_FAKE_SCENARIO = $Scenario
    $env:RULESET_FAKE_LOG = $Fixture.Log
    $env:RULESET_FAKE_STATE = $Fixture.State
    $env:RULESET_FAKE_OTHER_STATE = $Fixture.OtherState
    $env:RULESET_FAKE_PRODUCT_STATE = $Fixture.ProductState
    $env:RULESET_FAKE_NAME = [string](
        Get-Content -LiteralPath $Fixture.Ruleset -Raw | ConvertFrom-Json
    ).name
    $env:RULESET_FAKE_MAIN_OID = $Fixture.Head
}

function Set-RemoteRuleset {
    param($Fixture, [scriptblock]$Transform, [string]$StatePath = '')

    if ([string]::IsNullOrWhiteSpace($StatePath)) {
        $StatePath = $Fixture.State
    }
    $document = Get-Content -LiteralPath $Fixture.Ruleset -Raw |
        ConvertFrom-Json
    if ($null -ne $Transform) { & $Transform $document }
    Write-Utf8 $StatePath ($document | ConvertTo-Json -Depth 100)
}

function Set-RemoteLegacyRuleset {
    param($Fixture)

    Set-RemoteRuleset $Fixture {
        param($document)
        $rule = @($document.rules | Where-Object {
            $_.type -ceq 'required_status_checks'
        })[0]
        $rule.parameters.required_status_checks = @(
            @($rule.parameters.required_status_checks) + @(
                [pscustomobject][ordered]@{
                    context = 'Governance validation'
                    integration_id = 15368
                }
            )
        )
    }
}

function Set-RemoteProductRuleset {
    param($Fixture, [scriptblock]$Transform)

    $document = Get-Content -LiteralPath $Fixture.ProductRuleset -Raw |
        ConvertFrom-Json
    if ($null -ne $Transform) { & $Transform $document }
    Write-Utf8 `
        $Fixture.ProductState `
        ($document | ConvertTo-Json -Depth 100)
}

function Get-FakeCalls {
    param($Fixture, [string]$Prefix)

    if (-not [IO.File]::Exists($Fixture.Log)) { return @() }
    return @([IO.File]::ReadAllLines($Fixture.Log) | Where-Object {
        $_.StartsWith($Prefix, [StringComparison]::Ordinal)
    })
}

Export-ModuleMember -Function @(
    'Get-FakeCalls',
    'Initialize-LifecycleFixture',
    'Invoke-TestGit',
    'New-LifecycleFixture',
    'Set-FakeContext',
    'Set-RemoteLegacyRuleset',
    'Set-RemoteProductRuleset',
    'Set-RemoteRuleset',
    'Write-Utf8'
)
