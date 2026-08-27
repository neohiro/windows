# backup_recovery.ps1 -- Reminders & non-invasive recovery checks (no destructive actions)
$Module = 'backup_recovery'

function Set-BackupRecovery {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Backup & recovery reminders"

    $recoveryDrive = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.SizeGB -ge 4 }
    if (-not $recoveryDrive) {
        Write-Warn "No USB drive detected. Create a recovery drive (recoverydrive) before relying on BitLocker."
    } else {
        Write-Pass "Removable drive detected: $($recoveryDrive.DriveLetter) - run 'recoverydrive' to make a recovery drive."
    }

    $bdeStatus = Get-BitLockerVolume -ErrorAction SilentlyContinue
    if ($bdeStatus) {
        foreach ($v in $bdeStatus) {
            if ($v.KeyProtector.Count -lt 2) {
                Write-Warn "BitLocker on $($v.MountPoint) has only $($v.KeyProtector.Count) key protector(s) - add a backup."
            } else {
                Write-Pass "BitLocker on $($v.MountPoint) has $($v.KeyProtector.Count) key protectors."
            }
        }
    } else {
        Write-Info "No BitLocker volumes detected (or non-admin query)."
    }

    Add-Change $Module 'BackupChecks' 'informational' 'completed' $(if($DryRun){'DRY'}else{'OK'})
}

