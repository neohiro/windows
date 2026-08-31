# core.ps1 -- TPM, HVCI, LSA Protection, UAC, secure boot verification
$Module = 'core'

function Set-CoreSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Core isolation & LSA"
    $inv = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # LSA Protection (RunAsPPL)
    $cmd = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /t REG_DWORD /d 2 /f'
    & $inv $cmd
    Add-Change $Module 'RunAsPPL' '?' '2' $(if($DryRun){'DRY'}else{'OK'})

    # WDigest clear
    $cmd = 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest" /v UseLogonCredential /t REG_DWORD /d 0 /f'
    & $inv $cmd

    # LSA audit
    $cmd = 'reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\LSASS.exe" /v AuditLevel /t REG_DWORD /d 8 /f'
    & $inv $cmd

    # UAC: top slider
    $cmd = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 1 /f'
    & $inv $cmd
    $cmd = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 2 /f'
    & $inv $cmd
    $cmd = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v PromptOnSecureDesktop /t REG_DWORD /d 1 /f'
    & $inv $cmd

    # Secure boot / TPM informational checks
    try {
        $tpm = Get-Tpm -ErrorAction Stop
    } catch {
        $tpm = @{ TpmPresent = $false; TpmReady = $false }
    }
    if ($tpm.TpmPresent -and $tpm.TpmReady) {
        Write-Pass "TPM ready (spec $($tpm.SpecVersion))"
    } else {
        Write-Warn "TPM not ready. BitLocker, HVCI, Credential Guard need it."
    }

    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
    } catch {
        $secureBoot = $null
    }
    if ($secureBoot -eq $true) { Write-Pass "Secure Boot: ENABLED" }
    elseif ($secureBoot -eq $false) { Write-Warn "Secure Boot: DISABLED" }
    else { Write-Info "Secure Boot: not supported on this firmware" }

    # Credential Guard on Pro/Enterprise
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $edition = $os.Caption
    } catch {
        Write-Info "Get-CimInstance failed: $($_.Exception.Message). Skipping Credential Guard check."
        $edition = ''
    }
    if ($edition -match 'Pro|Enterprise|Education') {
        $cmd = 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 1 /f'
        & $inv $cmd
        $cmd = 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v RequirePlatformSecurityFeatures /t REG_DWORD /d 3 /f'
        & $inv $cmd
        $cmd = 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" /v LsaCfgFlags /t REG_DWORD /d 1 /f'
        & $inv $cmd
        Write-Pass "Credential Guard VBS policies set (reboot required)"
    } else {
        Write-Info "Home edition detected - Credential Guard policies skipped."
    }

    # Inactivity screen lock 15 min
    $cmd = 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v InactivityTimeoutSecs /t REG_DWORD /d 900 /f'
    & $inv $cmd
    $cmd = 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51" /v ACSettingIndex /t REG_DWORD /d 1 /f'
    & $inv $cmd
    $cmd = 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Power\PowerSettings\0e796bdb-100d-47d6-a2d5-f7d2daa51f51" /v DCSettingIndex /t REG_DWORD /d 1 /f'
    & $inv $cmd
}

