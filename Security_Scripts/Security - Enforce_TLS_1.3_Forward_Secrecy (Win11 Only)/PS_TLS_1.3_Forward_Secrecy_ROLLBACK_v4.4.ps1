<########################################################
    Name:       PS_TLS_1.3_Forward_Secrecy_ROLLBACK_v4.4.ps1
    Purpose:    Restores machine-wide TLS/SCHANNEL registry settings from a .reg backup
                created by REMEDIATE v4.4. Run manually by an admin when rollback is needed.
    Location:   Standalone (manual)
    Owner:      Darren Milne
    Comments:   By default restores from the EARLIEST backup on the device (true pre-remediation
                state). Machine-wide keys only; per-user SecureProtocols is out of scope.
                A reboot is required for SCHANNEL changes to fully take effect.

    STRUCTURE:
        1) Params and helpers
        2) Select backup file (earliest .reg by filename timestamp)
        3) reg import
        4) Exit

    CHANGELOG:  (dd/mm/yyyy)

        27/07/2026 - v4.4 - Initial release. Restore via reg import of REMEDIATE .reg backup
        28/07/2026 - v4.4 - Earliest backup selected by filename timestamp only

########################################################>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$BackupFile,

    [Parameter(Mandatory = $false)]
    [string]$BackupFolder = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TLS_1.3_Backups'
)

$ScriptVersion = '4.4'
$LogPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_TLS_1.3_Forward_Secrecy_ROLLBACK_v4.4.log'

function Get-BackupSortTimestampFromFileName {
    param([Parameter(Mandatory = $true)][string]$FilePath)

    if ($FilePath -match '_(\d{8}_\d{6})\.reg$') {
        return [datetime]::ParseExact($Matches[1], 'yyyyMMdd_HHmmss', $null)
    }

    return (Get-Item -LiteralPath $FilePath).CreationTimeUtc
}

function Get-RollbackBackupFile {
    param(
        [string]$ExplicitBackupFile,
        [string]$SearchFolder
    )

    if ($ExplicitBackupFile) {
        if (-not (Test-Path -LiteralPath $ExplicitBackupFile)) {
            throw "Backup file not found: $ExplicitBackupFile"
        }
        return (Resolve-Path -LiteralPath $ExplicitBackupFile).Path
    }

    if (-not (Test-Path -LiteralPath $SearchFolder)) {
        throw "Backup folder not found: $SearchFolder"
    }

    $backupFiles = Get-ChildItem -LiteralPath $SearchFolder -Filter 'TLS_1.3_Forward_Secrecy_Backup_*.reg' -File -ErrorAction Stop
    if (-not $backupFiles -or $backupFiles.Count -eq 0) {
        throw "No backup files found in $SearchFolder"
    }

    $selected = $backupFiles | Sort-Object {
        Get-BackupSortTimestampFromFileName -FilePath $_.FullName
    } | Select-Object -First 1

    return $selected.FullName
}

Start-Transcript -Path $LogPath -Append
$date = Get-Date -Format 'dddd dd/MM/yyyy'
Write-Host '--------------------------------------------------------------------------------'
Write-Host "Starting Rollback Script v$ScriptVersion - ($date)"
Write-Host '--------------------------------------------------------------------------------'

try {
    $selectedBackup = Get-RollbackBackupFile -ExplicitBackupFile $BackupFile -SearchFolder $BackupFolder
    Write-Host "Using backup file: $selectedBackup"

    if ($WhatIfPreference) {
        Write-Host 'Running in WhatIf mode - no registry changes will be made.'
        Write-Host '--------------------------------------------------------------------------------'
        Get-Content -LiteralPath $selectedBackup -Encoding Unicode | Write-Host
        Stop-Transcript | Out-Null
        exit 0
    }

    reg import $selectedBackup 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: reg import exited with code $LASTEXITCODE" -ForegroundColor Red
        Write-Host 'Note: A reboot is required for SCHANNEL changes to fully take effect.'
        Stop-Transcript | Out-Null
        exit 1
    }

    Write-Host 'Rollback completed successfully.' -ForegroundColor Green
    Write-Host 'Note: A reboot is required for SCHANNEL changes to fully take effect.'
    Stop-Transcript | Out-Null
    exit 0
} catch {
    Write-Host "FAILED: Rollback aborted ($($_.Exception.Message))" -ForegroundColor Red
    Stop-Transcript | Out-Null
    exit 1
}
