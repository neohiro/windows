# browser.ps1 -- Edge SmartScreen + Chrome enterprise policy
$Module = 'browser'

function Set-BrowserSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Browser hardening (Edge / Chrome / IE)"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # Edge SmartScreen
    & $do 'reg add "HKCU\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter" /v EnabledV9 /t REG_DWORD /d 1 /f'
    & $do 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v EnableSmartScreen /t REG_DWORD /d 1 /f'
    & $do 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" /v ShellSmartScreenLevel /t REG_SZ /d Block /f'

    # Disable IE installer addon prompts
    & $do 'reg add "HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer" /v SafeForScripting /t REG_DWORD /d 0 /f'

    # Chrome
    $chromePolicies = @(
        @{ V='AdvancedProtectionAllowed'; T='REG_DWORD'; D='1' }
        @{ V='AllowCrossOriginAuthPrompt'; T='REG_DWORD'; D='0' }
        @{ V='AlwaysOpenPdfExternally'; T='REG_DWORD'; D='1' }
        @{ V='AmbientAuthenticationInPrivateModesEnabled'; T='REG_DWORD'; D='0' }
        @{ V='AudioCaptureAllowed'; T='REG_DWORD'; D='0' }
        @{ V='AudioSandboxEnabled'; T='REG_DWORD'; D='1' }
        @{ V='BlockExternalExtensions'; T='REG_DWORD'; D='1' }
        @{ V='DnsOverHttpsMode'; T='REG_SZ'; D='on' }
        @{ V='SSLVersionMin'; T='REG_SZ'; D='tls1' }
        @{ V='ScreenCaptureAllowed'; T='REG_DWORD'; D='0' }
        @{ V='SitePerProcess'; T='REG_DWORD'; D='1' }
        @{ V='TLS13HardeningForLocalAnchorsEnabled'; T='REG_DWORD'; D='1' }
        @{ V='VideoCaptureAllowed'; T='REG_DWORD'; D='0' }
    )
    foreach ($p in $chromePolicies) {
        & $do "reg add `"HKLM\SOFTWARE\Policies\Google\Chrome`" /v `"$($p.V)`" /t $($p.T) /d $($p.D) /f"
    }

    Add-Change $Module 'Edge.SmartScreen' '?' 'enabled' $(if($DryRun){'DRY'}else{'OK'})
    Add-Change $Module 'Chrome.Policies' 'unset' 'hardened' $(if($DryRun){'DRY'}else{'OK'})
    Write-Pass "Browser policies applied."
}

