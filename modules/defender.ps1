# defender.ps1 -- Windows Defender hardening: ASR, Exploit Guard, PUA, cloud, Network Protection
$Module = 'defender'

$AsrRules = @(
    @{ Id = 'D4F940AB-401B-4EFC-AADC-AD5F3C50688A'; Name = 'BlockOfficeChildProcess' }
    @{ Id = '75668C1F-73B5-4CF0-BB93-3ECF5CB7CC84'; Name = 'BlockProcessInjection' }
    @{ Id = '92E97FA1-2EDF-4476-BDD6-9DD0B4DDDC7B'; Name = 'BlockWin32ApiCallsInMacros' }
    @{ Id = '3B576869-A4EC-4529-8536-B80A7769E899'; Name = 'BlockOfficeExecutableContent' }
    @{ Id = '5BEB7EFE-FD9A-4556-801D-275E5FFC04CC'; Name = 'BlockObfuscatedScripts' }
    @{ Id = 'BE9BA2D9-53EA-4CDC-84E5-9B1EEEE46550'; Name = 'BlockExecutableEmailContent' }
    @{ Id = 'D3E037E1-3EB8-44C8-A917-57927947596D'; Name = 'BlockJsVbScriptLaunchExe' }
    @{ Id = '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'; Name = 'BlockLsassCredTheft' }
    @{ Id = 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'; Name = 'BlockUntrustedUsb' }
    @{ Id = '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c'; Name = 'BlockAdobeReaderChild' }
    @{ Id = 'e6db77e5-3df2-4cf1-b95a-636979351e5b'; Name = 'BlockWmiPersistence' }
    @{ Id = 'd1e49aac-8f56-4280-b9ba-993a6d77406c'; Name = 'BlockPsExecWmi' }
)

function Set-DefenderSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Windows Defender & ASR rules"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # Service start
    & $do 'sc start WinDefend'

    # Sandbox
    $env:MP_FORCE_USE_SANDBOX = '1'
    & $do 'setx /M MP_FORCE_USE_SANDBOX 1'

    # PUA
    & $do 'powershell.exe -NoProfile -Command "Set-MpPreference -PUAProtection enable"'

    # Cloud + samples
    & $do 'powershell.exe -NoProfile -Command "Set-MpPreference -MAPSReporting Advanced"'
    & $do 'powershell.exe -NoProfile -Command "Set-MpPreference -SubmitSamplesConsent 0"'

    # Network protection
    & $do 'powershell.exe -NoProfile -Command "Set-MpPreference -EnableNetworkProtection Enabled"'

    # Early launch driver policy (default = 3 = good+unknown+bad-critical).
    # HKLM not HKCU: HKCU\SYSTEM is the user's mirror of the real HKLM\SYSTEM hive,
    # and writes there do NOT affect the kernel-mode DriverLoadPolicy enforcement.
    & $do 'reg add "HKLM\SYSTEM\CurrentControlSet\Policies\EarlyLaunch" /v DriverLoadPolicy /t REG_DWORD /d 3 /f'

    # ASR rules
    foreach ($rule in $AsrRules) {
        if ($AllowList -contains $rule.Name) {
            Write-Skip "ASR allow-listed: $($rule.Name)"
            Add-Change $Module "ASR:$($rule.Name)" 'enabled' 'ALLOWED' 'SKIP'
            continue
        }
        & $do "powershell.exe -NoProfile -Command `"Add-MpPreference -AttackSurfaceReductionRules_Ids $($rule.Id) -AttackSurfaceReductionRules_Actions Enabled -ErrorAction SilentlyContinue`""
        Add-Change $Module "ASR:$($rule.Name)" 'unset' 'Enabled' $(if($DryRun){'DRY'}else{'OK'})
    }

    # Exploit Protection (system-wide)
    & $do 'powershell.exe -NoProfile -Command "Set-ProcessMitigation -System -Enable DEP,EmulateAtlThunks,BottomUp,HighEntropy,SEHOP,SEHOPTelemetry,TerminateOnError -ErrorAction SilentlyContinue"'

    # Real-time monitor on
    & $do 'powershell.exe -NoProfile -Command "Set-MpPreference -DisableRealtimeMonitoring $false"'
    & $do 'reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Real-Time Protection" /v DisableRealtimeMonitoring /t REG_DWORD /d 0 /f'

    Write-Pass "Defender hardening applied."
}

