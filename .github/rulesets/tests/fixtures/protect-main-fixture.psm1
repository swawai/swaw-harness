$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$script:repositoryRoot = [IO.Path]::GetFullPath((Join-Path `
    $PSScriptRoot `
    '..\..\..\..'
))
$script:desiredSource = Join-Path `
    $script:repositoryRoot `
    '.github\rulesets\protect-main.json'
$script:sharedScriptsSource = Join-Path `
    $script:repositoryRoot `
    '.github\rulesets\scripts'
$script:git = Get-Command git -CommandType Application -ErrorAction Stop |
    Select-Object -First 1
$script:testRoot = ''

function Initialize-ProtectMainFixture {
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

function New-TestFixture {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($script:testRoot)) {
        throw 'Initialize-ProtectMainFixture must run before creating fixtures.'
    }
    $root = Join-Path $script:testRoot $Name
    $stateRoot = Join-Path $script:testRoot "state-$Name"
    $rulesetRoot = Join-Path $root '.github\rulesets'
    $scriptsRoot = Join-Path $rulesetRoot 'scripts'
    [void][IO.Directory]::CreateDirectory($rulesetRoot)
    [void][IO.Directory]::CreateDirectory($scriptsRoot)
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
    foreach ($source in [IO.Directory]::EnumerateFiles(
        $script:sharedScriptsSource
    )) {
        [IO.File]::Copy(
            $source,
            (Join-Path $scriptsRoot ([IO.Path]::GetFileName($source))),
            $true
        )
    }
    [IO.File]::WriteAllText((Join-Path $root 'seed.txt'), 'seed')
    [void](Invoke-TestGit $root @('add', '.'))
    [void](Invoke-TestGit $root @('commit', '-m', 'test: seed fixture'))
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
        State = Join-Path $stateRoot 'remote-ruleset.json'
        Ruleset = Join-Path $rulesetRoot 'protect-main.json'
        Script = Join-Path $scriptsRoot 'protect-main.ps1'
    }
}

function Set-FakeContext {
    param($Fixture, [string]$Scenario = 'happy')

    $env:RULESET_FAKE_SCENARIO = $Scenario
    $env:RULESET_FAKE_LOG = $Fixture.Log
    $env:RULESET_FAKE_STATE = $Fixture.State
    $env:RULESET_FAKE_OTHER_STATE = ''
    $env:RULESET_FAKE_PRODUCT_STATE = ''
    $env:RULESET_FAKE_NAME = [string](
        Get-Content -LiteralPath $Fixture.Ruleset -Raw | ConvertFrom-Json
    ).name
    $env:RULESET_FAKE_MAIN_OID = $Fixture.Head
}

function Set-RemoteRuleset {
    param($Fixture, [scriptblock]$Transform)

    $document = Get-Content -LiteralPath $Fixture.Ruleset -Raw |
        ConvertFrom-Json
    if ($null -ne $Transform) { & $Transform $document }
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

Export-ModuleMember -Function @(
    'Get-FakeCalls',
    'Initialize-ProtectMainFixture',
    'Invoke-TestGit',
    'New-TestFixture',
    'Set-FakeContext',
    'Set-RemoteRuleset'
)
