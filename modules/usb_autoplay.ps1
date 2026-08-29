# usb_autoplay.ps1 -- Disable autorun/autoplay, optional Print Spooler
$Module = 'usb_autoplay'

function Set-UsbAutoplaySettings {
    param([bool]$DryRun, [array]$AllowList, [switch]$AssumeYes, [switch]$ConfirmImpact)
    Write-Section "USB, AutoPlay & print spooler"

    # Disable autoplay everywhere via registry
    Invoke-Cmd -Cmd 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoAutoplayfornonVolume /t REG_DWORD /d 1 /f' -DryRun $DryRun
    Invoke-Cmd -Cmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f' -DryRun $DryRun
    Invoke-Cmd -Cmd 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoAutorun /t REG_DWORD /d 1 /f' -DryRun $DryRun

    Add-Change $Module 'AutoPlay' 'default' 'disabled' $(if($DryRun){'DRY'}else{'OK'})

    # Print Spooler: high-impact. Require typed "Yes"/"yes" unless -ConfirmImpact bypasses.
    if ($AllowList -contains 'KeepPrintSpooler') {
        Write-Skip "Print Spooler kept (allow-list)."
    } elseif ($ConfirmImpact) {
        Write-Info "-ConfirmImpact set; disabling Print Spooler without typed confirmation."
        Invoke-Cmd -Cmd 'powershell.exe -NoProfile -Command "Stop-Service Spooler -PassThru | Set-Service -StartupType Disabled"' -DryRun $DryRun
        Add-Change $Module 'Spooler' 'auto' 'disabled' $(if($DryRun){'DRY'}else{'OK'})
        Write-Pass "Print Spooler disabled."
    } else {
        $ok = Confirm-HighImpact -Action "Disable Print Spooler service" -Impact "NO PRINTING. All printers (USB, network, PDF) will stop working until service is re-enabled with: Set-Service Spooler -StartupType Automatic; Start-Service Spooler" -DryRun $DryRun
        if ($ok) {
            Invoke-Cmd -Cmd 'powershell.exe -NoProfile -Command "Stop-Service Spooler -PassThru | Set-Service -StartupType Disabled"' -DryRun $DryRun
            Add-Change $Module 'Spooler' 'auto' 'disabled' $(if($DryRun){'DRY'}else{'OK'})
            Write-Pass "Print Spooler disabled."
        } else {
            Add-Change $Module 'Spooler' 'unchanged' 'kept' 'SKIP'
        }
    }
}

