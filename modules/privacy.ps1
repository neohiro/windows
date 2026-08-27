# privacy.ps1 -- Telemetry, advertising ID, location, GameDVR, sync
$Module = 'privacy'

function Set-PrivacySettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Privacy & telemetry"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    $keys = @(
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection';     V='AllowTelemetry';     T='REG_DWORD'; D='0' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection';     V='MaxTelemetryAllowed';T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'; V='ShowedToastAtLevel'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore'; V='Location'; T='REG_SZ'; D='Deny' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search';       V='BingSearchEnabled'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search';       V='AllowSearchToUseLocation'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Search';       V='CortanaConsent'; T='REG_DWORD'; D='0' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\System';             V='PublishUserActivities'; T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\SettingSync';       V='DisableSettingSync'; T='REG_DWORD'; D='2' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo';    V='DisabledByGroupPolicy'; T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR';            V='AllowGameDVR'; T='REG_DWORD'; D='0' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent';       V='DisableWindowsConsumerFeatures'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; V='SystemPaneSuggestionsEnabled'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; V='SilentInstalledAppsEnabled'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; V='PreInstalledAppsEnabled'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; V='OemPreInstalledAppsEnabled'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\Control Panel\International\User Profile';              V='HttpAcceptLanguageOptOut'; T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'; V='NoToastApplicationNotificationOnLockScreen'; T='REG_DWORD'; D='1' }
    )

    foreach ($k in $keys) {
        & $do "reg add `"$($k.P)`" /v $($k.V) /t $($k.T) /d $($k.D) /f"
    }

    Add-Change $Module 'Privacy:All' 'defaults' 'telemetry-off+ad-id-off+location-deny' $(if($DryRun){'DRY'}else{'OK'})
    Write-Pass "Privacy settings applied."
}

