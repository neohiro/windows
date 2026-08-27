# browser.ps1 -- Edge SmartScreen + Chrome enterprise policy
$Module = 'browser'

function Set-BrowserSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Browser hardening (Edge / Chrome / IE)"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # Edge SmartScreen
    $edgeKeys = @(
        @{ P='HKCU\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter'; V='EnabledV9'; T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\System';              V='EnableSmartScreen';    T='REG_DWORD'; D='1' }
        @{ P='HKLM\SOFTWARE\Policies\Microsoft\Windows\System';              V='ShellSmartScreenLevel';T='REG_SZ';    D='Block' }
        @{ P='HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer';           V='SafeForScripting';    T='REG_DWORD'; D='0' }
    )
    $edgeOk = 0; $edgeErr = 0
    foreach ($k in $edgeKeys) {
        try {
            & $do "reg add `"$($k.P)`" /v $($k.V) /t $($k.T) /d $($k.D) /f"
            $edgeOk++
        } catch {
            Write-Warn "Browser reg add failed for $($k.P)\$($k.V): $_"
            Add-Change $Module "reg:$($k.P)\$($k.V)" 'unset' 'failed' 'ERR'
            $edgeErr++
        }
    }
    Add-Change $Module 'Edge.SmartScreen' '?' 'enabled' $(if($DryRun){'DRY'}else{if($edgeErr -eq 0){'OK'}else{'partial'}})

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
    $chromeOk = 0; $chromeErr = 0
    foreach ($p in $chromePolicies) {
        try {
            & $do "reg add `"HKLM\SOFTWARE\Policies\Google\Chrome`" /v `"$($p.V)`" /t $($p.T) /d $($p.D) /f"
            $chromeOk++
        } catch {
            Write-Warn "Chrome policy reg add failed for $($p.V): $_"
            Add-Change $Module "reg:Chrome\$($p.V)" 'unset' 'failed' 'ERR'
            $chromeErr++
        }
    }
    $chromeStatus = if ($chromeErr -gt 0) { 'partial' } else { 'hardened' }
    Add-Change $Module 'Chrome.Policies' 'unset' $chromeStatus $(if($DryRun){'DRY'}else{if($chromeErr -eq 0){'OK'}else{'partial'}})
    Write-Pass "Browser policies applied."
}

