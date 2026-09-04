Set-StrictMode -Version 2.0

function Test-SwawHarnessRunAnnouncement {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value -cmatch '^\[RUN\] [a-f0-9]{32}$'
}

function Test-SwawHarnessUserCreation {
    param(
        [Parameter(Mandatory = $true)][string]$TestRoot,
        [Parameter(Mandatory = $true)][string]$ModuleAdminRoot,
        [Parameter(Mandatory = $true)][object]$AdminHost,
        [Parameter(Mandatory = $true)][string]$PlatformTargetId,
        [Parameter(Mandatory = $true)][string]$HostModuleVersion
    )

    $DataHome = Join-Path $TestRoot 'data'
    $CreateAlice = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('core/admin/user/create', 'alice') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    $AliceHome = Join-Path $DataHome 'alice'
    $AliceCli = Join-Path $DataHome 'alice.exe'
    $AliceRecordPath = Join-Path $AliceHome 'user.json'
    $AliceRecord = Read-SwawHarnessJsonFile `
        -Path $AliceRecordPath `
        -Description 'Alice Harness User record'
    Assert-SwawHarnessObjectFields `
        -Value $AliceRecord `
        -Expected @('schema', 'userId', 'lifecycle', 'userCli') `
        -Description 'Alice Harness User record'
    Assert-SwawHarnessObjectFields `
        -Value $AliceRecord.userCli `
        -Expected @('length', 'sha256') `
        -Description 'Alice User CLI identity'
    $AlicePointerPath = Join-Path $AliceHome (
        'host\current.' + $PlatformTargetId
    )
    if ($CreateAlice.ExitCode -ne 0 -or
        -not [string]::IsNullOrEmpty($CreateAlice.Output) -or
        -not (Test-SwawHarnessRunAnnouncement -Value $CreateAlice.Error) -or
        [string]$AliceRecord.schema -cne 'swaw.harness.user/v1' -or
        [string]$AliceRecord.userId -cne 'alice' -or
        [string]$AliceRecord.lifecycle -cne 'active' -or
        -not [IO.File]::Exists($AliceCli) -or
        [long]$AliceRecord.userCli.length -ne
            (Get-Item -LiteralPath $AliceCli -Force).Length -or
        [string]$AliceRecord.userCli.sha256 -cne
            (Get-SwawHarnessFileSha256 -Path $AliceCli) -or
        (Get-SwawHarnessFileSha256 -Path $AliceCli) -cne
            (Get-SwawHarnessFileSha256 -Path $AdminHost.UserCliPath) -or
        [IO.File]::ReadAllText($AlicePointerPath).TrimEnd("`r", "`n") -cne
            $HostModuleVersion -or
        -not [IO.File]::Exists((Join-Path $AliceHome `
            'map\core\admin\user\create\skill.toml')) -or
        -not [IO.File]::Exists((Join-Path $ModuleAdminRoot 'user.lock'))) {
        throw 'Admin User creation did not publish a complete active Alice.'
    }
    $AliceHello = Invoke-SwawHarnessCapturedProcess `
        -Executable $AliceCli `
        -Arguments @('core/helloworld', 'Alice') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    if ($AliceHello.ExitCode -ne 0 -or
        $AliceHello.Output -cne 'Hello, Alice!' -or
        -not (Test-SwawHarnessRunAnnouncement -Value $AliceHello.Error)) {
        throw 'Alice User CLI did not invoke her copied Core Skill Map.'
    }

    [void][IO.Directory]::CreateDirectory(
        (Join-Path $ModuleAdminRoot 'map\core\later')
    )
    $AliceRecordHash = Get-SwawHarnessFileSha256 -Path $AliceRecordPath
    $RepeatAlice = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('core/admin/user/create', 'alice') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    if ($RepeatAlice.ExitCode -ne 0 -or
        -not [string]::IsNullOrEmpty($RepeatAlice.Output) -or
        -not (Test-SwawHarnessRunAnnouncement -Value $RepeatAlice.Error) -or
        (Get-SwawHarnessFileSha256 -Path $AliceRecordPath) -cne
            $AliceRecordHash -or
        [IO.Directory]::Exists((Join-Path $AliceHome 'map\core\later'))) {
        throw 'Repeated Harness User creation was not an independent no-op.'
    }

    $CreateRecover = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('core/admin/user/create', 'recover') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    $RecoverHome = Join-Path $DataHome 'recover'
    $RecoverCli = Join-Path $DataHome 'recover.exe'
    $RecoverRecordPath = Join-Path $RecoverHome 'user.json'
    $RecoverRecord = Read-SwawHarnessJsonFile `
        -Path $RecoverRecordPath `
        -Description 'Recover Harness User record'
    $RecoverRecord.lifecycle = 'creating'
    [IO.File]::WriteAllText(
        $RecoverRecordPath,
        (($RecoverRecord | ConvertTo-Json -Depth 8) + "`n"),
        [Text.UTF8Encoding]::new($false)
    )
    $InactiveRecover = Invoke-SwawHarnessCapturedProcess `
        -Executable $RecoverCli `
        -Arguments @('core/helloworld') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    [IO.File]::Delete($RecoverCli)
    $ResumeRecover = Invoke-SwawHarnessCapturedProcess `
        -Executable $AdminHost.UserCliPath `
        -Arguments @('core/admin/user/create', 'recover') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    $RecoveredRecord = Read-SwawHarnessJsonFile `
        -Path $RecoverRecordPath `
        -Description 'recovered Harness User record'
    if ($CreateRecover.ExitCode -ne 0 -or $InactiveRecover.ExitCode -ne 1 -or
        -not [string]::IsNullOrEmpty($InactiveRecover.Output) -or
        $InactiveRecover.Error -cnotmatch '^\[ERROR\] Cannot connect' -or
        $ResumeRecover.ExitCode -ne 0 -or
        [string]$RecoveredRecord.lifecycle -cne 'active' -or
        -not [IO.File]::Exists($RecoverCli)) {
        throw 'Harness User lifecycle recovery or inactive Host gate failed.'
    }

    $CreateBob = Invoke-SwawHarnessCapturedProcess `
        -Executable $AliceCli `
        -Arguments @('core/admin/user/create', 'bob') `
        -WorkingDirectory $DataHome `
        -TimeoutSeconds 30
    $BobRecord = Read-SwawHarnessJsonFile `
        -Path (Join-Path $DataHome 'bob\user.json') `
        -Description 'Bob Harness User record'
    if ($CreateBob.ExitCode -ne 0 -or
        [string]$BobRecord.lifecycle -cne 'active') {
        throw 'Issue 53 must not introduce special Admin module authorization.'
    }
}
