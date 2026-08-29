# usb_autoplay.ps1 -- Disable autorun/autoplay, optional Print Spooler
$Module = 'usb_autoplay'

function Set-UsbAutoplaySettings {
    param([bool]$DryRun, [array]$AllowList, [switch]$AssumeYes)
    Write-Section "USB, AutoPlay & print spooler"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # Autoplay off everywhere
    & $do 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v NoAutoplayfornonVolume /t REG_DWORD /d 1 /f'
    & $do 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoDriveTypeAutoRun /t REG_DWORD /d 255 /f'
    & $do 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoAutorun /t REG_DWORD /d 1 /f'

    Add-Change $Module 'AutoPlay' 'default' 'disabled' $(if($DryRun){'DRY'}else{'OK'})

    # Print spooler - prompt if user wants it off
    if ($AllowList -contains 'KeepPrintSpooler') {
        Write-Skip "Print Spooler kept (allow-list)."
    } elseif ($AssumeYes) {
        Write-Warn "-AssumeYes set; DISABLING Print Spooler (impact: NO PRINTING. All printers, USB/network/PDF, will stop working until re-enabled)."
        & $do 'powershell.exe -NoProfile -Command "Stop-Service Spooler -PassThru | Set-Service -StartupType Disabled"'
        Add-Change $Module 'Spooler' 'auto' 'disabled' $(if($DryRun){'DRY'}else{'OK'})
        Write-Pass "Print Spooler disabled."
    } else {
        $resp = Invoke-TimedPrompt -Message "Disable Print Spooler service? (PrintNightmare mitigation; impact: NO PRINTING. Use N if you have a printer)" -Default 'N' -ValidChars @('Y','N','S')
        if ($resp -eq 'Y') {
            & $do 'powershell.exe -NoProfile -Command "Stop-Service Spooler -PassThru | Set-Service -StartupType Disabled"'
            Add-Change $Module 'Spooler' 'auto' 'disabled' $(if($DryRun){'DRY'}else{'OK'})
            Write-Pass "Print Spooler disabled."
        } else {
            Add-Change $Module 'Spooler' 'unchanged' 'kept' 'SKIP'
        }
    }
}

