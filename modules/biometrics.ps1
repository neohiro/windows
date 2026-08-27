# biometrics.ps1 -- Anti-spoofing, lock screen camera, voice activation
$Module = 'biometrics'

function Set-BiometricsSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Biometrics & lock screen"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    $keys = @(
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Biometrics\FacialFeatures'; V='EnhancedAntiSpoofing'; T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization';  V='NoLockScreenCamera'; T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';       V='LetAppsActivateWithVoiceAboveLock'; T='REG_DWORD'; D='2' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';       V='LetAppsActivateWithVoice'; T='REG_DWORD'; D='2' }
    )
    $okCount = 0; $errCount = 0
    foreach ($k in $keys) {
        try {
            & $do "reg add `"$($k.P)`" /v $($k.V) /t $($k.T) /d $($k.D) /f"
            $okCount++
        } catch {
            Write-Warn "Biometrics reg add failed for $($k.P)\$($k.V): $_"
            Add-Change $Module "reg:$($k.P)\$($k.V)" 'unset' 'failed' 'ERR'
            $errCount++
        }
    }
    $status = if ($errCount -gt 0) { 'partial' } else { 'OK' }
    Add-Change $Module 'Biometrics' 'defaults' "${okCount}ok/${errCount}err" $(if($DryRun){'DRY'}else{$status})
    Write-Pass "Biometrics / lock screen hardened."
}

