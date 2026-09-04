Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot '..\builder\foundation.ps1')
. (Join-Path $PSScriptRoot '..\builder\filesystem.ps1')

function Invoke-SwawHarnessInstallValidation {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Validate,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $Result = @(& $Validate $InstallRoot)
    if ($Result.Count -ne 1 -or $Result[0] -isnot [bool]) {
        throw "$Name validator must return exactly one Boolean."
    }
    return [bool]$Result[0]
}

function Publish-SwawHarnessInstallDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$StagedPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ControlledRoot,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Validate
    )

    $TargetPath = Assert-SwawHarnessPathInsideRoot `
        -Path $TargetPath `
        -Root $ControlledRoot `
        -Activity 'publishing a Bootstrap installation'
    $StagedPath = Assert-SwawHarnessPathInsideRoot `
        -Path $StagedPath `
        -Root $ControlledRoot `
        -Activity 'publishing a staged Bootstrap installation'
    $StagedItem = Get-Item `
        -LiteralPath $StagedPath `
        -Force `
        -ErrorAction SilentlyContinue
    if ($null -eq $StagedItem -or -not $StagedItem.PSIsContainer -or
        ($StagedItem.Attributes -band
            [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not (Invoke-SwawHarnessInstallValidation `
            -Validate $Validate `
            -InstallRoot $StagedPath `
            -Name $Name)) {
        throw "Staged $Name installation failed validation: $StagedPath"
    }

    [void][IO.Directory]::CreateDirectory(
        (Split-Path -Path $TargetPath -Parent)
    )
    $Published = $false

    try {
        if (Test-SwawHarnessPathExists -Path $TargetPath) {
            throw "Content-addressed $Name target already exists: $TargetPath"
        }
        Move-SwawHarnessControlledPathWithRetry `
            -Source $StagedPath `
            -Destination $TargetPath `
            -ControlledRoot $ControlledRoot `
            -Activity 'publishing the staged installation'
        $Published = $true
        if (-not (Invoke-SwawHarnessInstallValidation `
            -Validate $Validate `
            -InstallRoot $TargetPath `
            -Name $Name
        )) {
            throw "Published $Name installation failed validation."
        }
    } catch {
        $PublishError = $_
        if ($Published -and
            (Test-SwawHarnessPathExists -Path $TargetPath)) {
            try {
                Remove-SwawHarnessControlledPathWithRetry `
                    -Path $TargetPath `
                    -ControlledRoot $ControlledRoot `
                    -Activity 'removing a failed content-addressed installation'
            } catch {
                throw (
                    "Publishing $Name failed and the invalid target could " +
                    "not be removed: '$TargetPath'. Original error: " +
                    "$($PublishError.Exception.Message). Cleanup error: " +
                    $_.Exception.Message
                )
            }
        }
        throw $PublishError
    } finally {
        if (Test-SwawHarnessPathExists -Path $StagedPath) {
            Remove-SwawHarnessControlledResidues `
                -ControlledRoot $ControlledRoot `
                -Paths @($StagedPath) `
                -Activity 'cleaning a staged installation'
        }
    }
}
