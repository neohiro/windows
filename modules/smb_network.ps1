# smb_network.ps1 -- SMB1, LLMNR, NetBIOS, ICMP redirect, RPC, WinRM
$Module = 'smb_network'

$Settings = @(
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v EnableMulticast /t REG_DWORD /d 0 /f'; Key='DNSClient:EnableMulticast'; AllowKey='DisableMulticastDNS' }
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v DisableSmartNameResolution /t REG_DWORD /d 1 /f'; Key='DNSClient:DisableSmartNameResolution'; AllowKey='DisableSmartNameResolution' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v DisableParallelAandAAAA /t REG_DWORD /d 1 /f'; Key='Dnscache:Parallel'; AllowKey='DisableParallelDns' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v EnableICMPRedirect /t REG_DWORD /d 0 /f'; Key='Tcpip:ICMPRedirect'; AllowKey='DisableIcmpRedirect' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DisableIPSourceRouting /t REG_DWORD /d 2 /f'; Key='Tcpip:IPSourceRouting'; AllowKey='DisableIPSourceRouting' }
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WcmSvc\GroupPolicy" /v fMinimizeConnections /t REG_DWORD /d 1 /f'; Key='WcmSvc:MinConnections'; AllowKey='MinimizeConnections' }
    @{ Action='reg add "HKLM\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config" /v AutoConnectAllowedOEM /t REG_DWORD /d 0 /f'; Key='WcmSvc:AutoConnect'; AllowKey='DisableWifiAutoConnect' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\Netbt\Parameters" /v NoNameReleaseOnDemand /t REG_DWORD /d 1 /f'; Key='Netbt:NoNameRelease'; AllowKey='NoNameRelease' }
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Rpc" /v RestrictRemoteClients /t REG_DWORD /d 1 /f'; Key='Rpc:RestrictRemote'; AllowKey='RestrictRemoteRpc' }
    @{ Action='powershell.exe -NoProfile -Command "Disable-WindowsOptionalFeature -Online -FeatureName smb1protocol -norestart"'; Key='SMB1Protocol'; AllowKey='DisableSMB1' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\mrxsmb10" /v Start /t REG_DWORD /d 4 /f'; Key='mrxsmb10:Start'; AllowKey='DisableSMB1' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v SMB1 /t REG_DWORD /d 0 /f'; Key='Lanman:SMB1'; AllowKey='DisableSMB1' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" /v RestrictNullSessAccess /t REG_DWORD /d 1 /f'; Key='Lanman:NullSession'; AllowKey='RestrictNullSession' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RestrictAnonymous /t REG_DWORD /d 1 /f'; Key='Lsa:RestrictAnonymous'; AllowKey='RestrictAnonymous' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RestrictAnonymousSAM /t REG_DWORD /d 1 /f'; Key='Lsa:RestrictAnonymousSAM'; AllowKey='RestrictAnonymousSAM' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v EveryoneIncludesAnonymous /t REG_DWORD /d 0 /f'; Key='Lsa:EveryoneIncludesAnonymous'; AllowKey='RemoveAnonymous' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v LimitBlankPasswordUse /t REG_DWORD /d 1 /f'; Key='Lsa:LimitBlankPassword'; AllowKey='LimitBlankPasswords' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v EnableSecuritySignature /t REG_DWORD /d 1 /f'; Key='LanmanWork:ClientSigning'; AllowKey='EnableSmbClientSigning' }
    @{ Action='reg add "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" /v EnablePlainTextPassword /t REG_DWORD /d 0 /f'; Key='LanmanWork:PlainText'; AllowKey='DisablePlainTextPassword' }
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation" /v AllowInsecureGuestAuth /t REG_DWORD /d 0 /f'; Key='LanmanWork:InsecureGuest'; AllowKey='DisableInsecureGuest' }
    # Disable NetBIOS over TCP per-interface via the registry. wmic.exe is
    # deprecated as of Windows 11 22H2; the per-interface NetbiosOptions DWORD
    # under Netbt\Parameters\Interfaces\<Tcpip_GUID> is the same setting wmic
    # manipulated, but works on every Windows release without depending on the
    # wmic optional feature. Value 1 disables NetBIOS-over-TCP.
    # We defer the actual enumeration to Set-SmbNetworkSettings (it needs the
    # registry to be live-read at run time, not parse-time).
    @{ Action='__per_interface_netbios'; Key='NetBIOS-on-TCP'; AllowKey='DisableNetBIOS' }
    @{ Action='net stop WinRM'; Key='WinRM:Stop'; AllowKey='StopWinRM' }
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" /v AllowUnencryptedTraffic /t REG_DWORD /d 0 /f'; Key='WinRM:Unencrypted'; AllowKey='StopWinRM' }
    @{ Action='reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" /v AllowDigest /t REG_DWORD /d 0 /f'; Key='WinRM:Digest'; AllowKey='StopWinRM' }
    @{ Action='reg add "HKLM\Software\Microsoft\Windows NT\CurrentVersion\Schedule" /v DisableRpcOverTcp /t REG_DWORD /d 1 /f'; Key='Schedule:RpcOverTcp'; AllowKey='BlockRemoteSchedule' }
    @{ Action='reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control" /v DisableRemoteScmEndpoints /t REG_DWORD /d 1 /f'; Key='SCM:RemoteEndpoints'; AllowKey='BlockRemoteSCM' }
)

function Set-SmbNetworkSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "SMB & network protocols"

    foreach ($s in $Settings) {
        if ($AllowList -contains $s.AllowKey) {
            Write-Skip "Setting allow-listed: $($s.Key)"
            Add-Change $Module $s.Key 'unset' 'ALLOWED' 'SKIP'
            continue
        }

        # Some hardening steps need richer logic than a single shell command
        # (e.g. enumerating per-interface registry subkeys). They are dispatched
        # by sentinel action name so the simple-command path stays fast and
        # dry-run cheap.
        if ($s.Action -eq '__per_interface_netbios') {
            Set-NetbiosPerInterface -DryRun:$DryRun
            continue
        }

        if ($DryRun) { Write-Info "DRY-RUN: $($s.Action)"; Add-Change $Module $s.Key 'unset' 'preview' 'DRY' }
        else {
            try {
                Invoke-Cmd -Cmd $s.Action -DryRun $DryRun
                Add-Change $Module $s.Key 'unset' 'applied' 'OK'
            } catch {
                Add-Change $Module $s.Key 'unset' 'failed' 'ERR'
            }
        }
    }

    # Kerberos hardening
    if ($AllowList -notcontains 'DisableWeakKerberos') {
        if ($DryRun) {
            Add-Change $Module 'Kerberos:EncryptionTypes' 'mixed' 'AES-only' 'DRY'
        } else {
            try {
                $null = reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" /v SupportedEncryptionTypes /t REG_DWORD /d 2147483640 /f
                if ($LASTEXITCODE -ne 0) { throw "reg add exited $LASTEXITCODE" }
                Add-Change $Module 'Kerberos:EncryptionTypes' 'mixed' 'AES-only' 'OK'
            } catch {
                Write-Warn "Kerberos hardening failed: $($_.Exception.Message)"
                Add-Change $Module 'Kerberos:EncryptionTypes' 'mixed' 'failed' 'ERR'
            }
        }
    }
    Write-Pass "SMB/network protocol hardening complete."
}

# Disables NetBIOS-over-TCP on every enabled Tcpip interface by writing the
# NetbiosOptions DWORD under the Netbt\Parameters\Interfaces subkey that
# matches the interface GUID. This replaces the wmic.exe call (deprecated in
# Win11 22H2) and works on every supported Windows release without requiring
# the wmic optional feature to be installed.
function Set-NetbiosPerInterface {
    param([bool]$DryRun)

    $tcpipBase = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $netbtBase = 'HKLM:\SYSTEM\CurrentControlSet\Services\Netbt\Parameters\Interfaces'

    if (-not (Test-Path $tcpipBase)) {
        Write-Skip "No Tcpip interfaces to harden"
        Add-Change $Module 'NetBIOS-on-TCP' 'unset' 'no-iface' 'SKIP'
        return
    }

    $guids = Get-ChildItem $tcpipBase -ErrorAction SilentlyContinue |
             ForEach-Object { $_.PSChildName }
    if (-not $guids) {
        Write-Skip "No Tcpip interface GUIDs found"
        Add-Change $Module 'NetBIOS-on-TCP' 'unset' 'no-iface' 'SKIP'
        return
    }

    $okCount = 0
    $errCount = 0
    foreach ($g in $guids) {
        $target = Join-Path $netbtBase $g
        if ($DryRun) {
            Write-Info "DRY-RUN: would set $target NetbiosOptions=1"
            $okCount++
            continue
        }
        try {
            if (-not (Test-Path $target)) {
                New-Item -Path $target -Force | Out-Null
            }
            New-ItemProperty -Path $target -Name 'NetbiosOptions' -Value 1 -PropertyType DWord -Force | Out-Null
            $okCount++
        } catch {
            Write-Warn "NetBIOS hardening failed for $g : $($_.Exception.Message)"
            $errCount++
        }
    }

    $status = if ($errCount -gt 0) { 'partial' } else { 'applied' }
    Add-Change $Module 'NetBIOS-on-TCP' 'mixed' "${okCount}ok/${errCount}err" $status
}

