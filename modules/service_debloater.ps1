# service_debloater.ps1 -- Interactive service debloater with allow-list + snapshot
$Module = 'service_debloater'

# Default catalog: service name, friendly description, default action, and impact.
# Impact describes the USER-FACING ABILITY that is lost or degraded when disabled.
# Format: "Loses X" or "Degrades X" or "Requires restart: X"
# These are shown in the interactive prompt so users make informed choices.
$DefaultServices = @(
    @{ Name='DiagTrack';       Desc='Connected User Experiences & Telemetry'; DefaultAction='Disabled'; Impact='CEIP telemetry sent to Microsoft; personalization features may degrade' }
    @{ Name='dmwappushservice';Desc='WAPPushService (device metadata wireless)';  DefaultAction='Disabled'; Impact='Some third-party apps may not receive push notifications' }
    @{ Name='HomeGroupListener';Desc='HomeGroup Listener (Win10 only)';           DefaultAction='Disabled'; Impact='HomeGroup file sharing does not work (HomeGroup deprecated since Win10 1803)' }
    @{ Name='HomeGroupProvider';Desc='HomeGroup Provider (Win10 only)';            DefaultAction='Disabled'; Impact='HomeGroup file sharing does not work (HomeGroup deprecated since Win10 1803)' }
    @{ Name='lfsvc';           Desc='Geolocation Service';                       DefaultAction='Disabled'; Impact='Maps apps cannot determine device location; some weather apps degrade' }
    @{ Name='MapsBroker';       Desc='Downloaded Maps Manager';                   DefaultAction='Disabled'; Impact='Offline maps cannot be downloaded or updated' }
    @{ Name='NetTcpPortSharing';Desc='Net.Tcp Port Sharing';                      DefaultAction='Disabled'; Impact='WCF services relying on net.tcp binding cannot start' }
    @{ Name='RemoteAccess';     Desc='Routing and Remote Access';                 DefaultAction='Disabled'; Impact='VPN and DirectAccess connectivity is disabled' }
    @{ Name='RemoteRegistry';   Desc='Remote Registry';                           DefaultAction='Disabled'; Impact='Other computers cannot read this machine registry remotely (security gain)' }
    @{ Name='RetailDemo';       Desc='Retail Demo Mode';                          DefaultAction='Disabled'; Impact='Retail store demo mode unavailable (unlikely to affect any real user)' }
    @{ Name='SharedAccess';    Desc='ICS (Internet Connection Sharing)';         DefaultAction='Disabled'; Impact='Cannot share internet connection with other devices (tethering hotspot)' }
    @{ Name='sshd';            Desc='OpenSSH Server';                            DefaultAction='Disabled'; Impact='SSH server not running; cannot SSH into this machine' }
    @{ Name='TrkWks';          Desc='Distributed Link Tracking Client';           DefaultAction='Disabled'; Impact='Shortcuts and linked files on network shares may break across renames' }
    @{ Name='WbioSrvc';        Desc='Windows Biometric Service';                  DefaultAction='Manual';   Impact='Windows Hello fingerprint/face login unavailable; biometric APIs fail' }
    @{ Name='WMPNetworkSvc';   Desc='Windows Media Player network sharing';       DefaultAction='Disabled'; Impact='DLNA/UPnP media streaming from WMP to TVs/speakers is disabled' }
    @{ Name='WerSvc';          Desc='Windows Error Reporting';                   DefaultAction='Disabled'; Impact='Error reports not sent to Microsoft; no Problem Reports tool data' }
    @{ Name='XblAuthManager';  Desc='Xbox Live Auth Manager';                    DefaultAction='Disabled'; Impact='Xbox social features, game invites, and cross-play may fail' }
    @{ Name='XblGameSave';     Desc='Xbox Live Game Save';                       DefaultAction='Disabled'; Impact='Xbox cloud save sync for some games unavailable' }
    @{ Name='XboxGipSvc';      Desc='Xbox Accessory Management Service';          DefaultAction='Disabled'; Impact='Xbox controllers connected via wireless may not work' }
    @{ Name='XboxNetApiSvc';   Desc='Xbox Live Networking Service';               DefaultAction='Disabled'; Impact='Xbox multiplayer and party chat may be impaired' }
    @{ Name='PrintSpooler';    Desc='Print Spooler (PrintNightmare)';            DefaultAction='Disabled'; Impact='NO PRINTING. All printers (USB, network, PDF) will stop working until service restarts' }
    @{ Name='Fax';             Desc='Fax Service';                               DefaultAction='Disabled'; Impact='Windows Fax and Scan cannot send/receive faxes' }
    @{ Name='TabletInputService'; Desc='Touch Keyboard & Handwriting Panel';     DefaultAction='Disabled'; Impact='On-screen keyboard (OSK) and handwriting panel unavailable; accessibility risk' }
    @{ Name='WSearch';         Desc='Windows Search Indexer';                    DefaultAction='Manual';   Impact='Search in Start menu and File Explorer is slower; indexed search disabled' }
    @{ Name='SysMain';         Desc='SysMain (Superfetch)';                      DefaultAction='Manual';   Impact='Memory compression and prefetch reduced; apps may launch more slowly after reboot' }
    @{ Name='CDPUserSvc';      Desc='Connected Devices Platform User';            DefaultAction='Disabled'; Impact='Clipboard sync between PC and phone, Cast to Device, Projecting may fail' }
    @{ Name='OneSyncSvc';      Desc='Sync Host (Mail/Calendar/People)';          DefaultAction='Disabled'; Impact='Mail, Calendar, People, and other UWP apps stop syncing Microsoft account data' }
    @{ Name='UnistoreSvc';     Desc='User Data Storage';                         DefaultAction='Disabled'; Impact='UWP apps cannot save/load structured user data (contacts, tasks)' }
    @{ Name='PimIndexMaintenanceSvc'; Desc='Contact Data';                       DefaultAction='Disabled'; Impact='Contact search and merging in People app is unavailable' }
    @{ Name='BcastDVRUserService'; Desc='GameDVR & Broadcast User Service';     DefaultAction='Disabled'; Impact='Xbox Game Bar recording and broadcasting features unavailable' }
    @{ Name='CaptureService';  Desc='CaptureService (screenshots)';              DefaultAction='Disabled'; Impact='Some screenshot/scREEN capture APIs and built-in snipping tool may degrade' }
    @{ Name='FrameServer';     Desc='Camera Frame Server';                       DefaultAction='Disabled'; Impact='Multiple simultaneous camera app access may fail; some webcam apps may not work' }
    @{ Name='edgeupdate';      Desc='Edge Update Service (edgeupdate)';           DefaultAction='Manual';   Impact='Microsoft Edge cannot auto-update itself' }
    @{ Name='edgeupdatem';     Desc='Edge Update Service (edgeupdatem)';          DefaultAction='Manual';   Impact='Microsoft Edge (machine-level) cannot auto-update itself' }
)

function Get-ServiceCatalog {
    return $DefaultServices
}

function Set-ServiceDebloater {
    param([bool]$DryRun, [array]$AllowList, [switch]$AssumeYes)
    Write-Section "Service Debloater (interactive)"

    # Snapshot before changes. Skip in dry-run: snapshots call reg export for
    # five hives plus dump every service, which is wasted I/O when no changes
    # are being made. The orchestrator already takes a pre-hardening snapshot
    # for real runs.
    $snap = $null
    if (-not $DryRun) {
        $snap = New-Snapshot -Label "service-debloat-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Info "Service snapshot: $snap"
    }

    $items = @()
    foreach ($svc in $DefaultServices) {
        $existing = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($existing) {
            $items += [PSCustomObject]@{
                Name         = $svc.Name
                Desc         = $svc.Desc
                Impact       = $svc.Impact
                StartType    = $existing.StartType
                Status       = $existing.Status
                Default      = $svc.DefaultAction
                Action       = $svc.DefaultAction
                AllowListed  = $AllowList -contains $svc.Name
            }
        } else {
            Add-Change $Module "service:$($svc.Name)" 'not-installed' 'n/a' 'SKIP'
        }
    }

    # In non-interactive context (CI, piped input, hidden window), ReadKey would
    # block forever. Apply the default action to each service instead.
    $interactive = Test-IsInteractive
    if (-not $interactive) {
        Write-Info "Non-interactive session detected; applying default actions without prompts."
    } elseif ($AssumeYes) {
        Write-Info "-AssumeYes set; applying default actions without prompts (all choices accepted)."
    } else {
        $pending = @($items | Where-Object { -not $_.AllowListed -and $_.Action -ne $_.StartType.ToString() })
        if ($pending.Count -gt 0) {
            # Pre-action summary: list every service about to be changed so the user
            # can see impact at a glance before answering any per-item prompts.
            Write-Host ""
            Write-Host "=== Pending service changes (default actions) ===" -ForegroundColor Cyan
            foreach ($it in $pending) {
                Write-Host ("  {0,-22} {1,-50} -> {2}" -f $it.Name, $it.Desc, $it.Action) -ForegroundColor White
                Write-Host ("     impact: {0}" -f $it.Impact) -ForegroundColor DarkGray
            }
            Write-Host ""
            $bulk = Invoke-TimedPrompt -Message "Apply these default actions? [Y=Yes, N=No (review each), A=Allow-list all of them]" -Default 'N' -ValidChars @('Y','N','A')
            if ($bulk -eq 'A') {
                foreach ($it in $items) {
                    if (-not $it.AllowListed -and $it.Action -ne $it.StartType.ToString()) {
                        $it.AllowListed = $true
                        Add-Change $Module "service:$($it.Name)" 'added-to-allowlist' 'no-change' 'SKIP'
                    }
                }
            } elseif ($bulk -eq 'Y') {
                # Apply defaults silently; skip per-item loop
                $AssumeYes = $true
            }
            # N falls through to per-item prompts below
        } else {
            Write-Info "No service start-type changes pending; skipping bulk prompt."
        }
    }

    $index = 0
    while ($index -lt $items.Count) {
        $it = $items[$index]
        $status = if ($it.Status -eq 'Running') { '[running]' } else { '[stopped]' }
        $st = if ($it.AllowListed) { '[ALLOW-LISTED]' } else { "[$($it.StartType) -> $($it.Action)]" }

        Write-Host ""
        Write-Host ("[{0,2}/{1,-2}] {2}  ({3})  {4}  {5}" -f ($index+1), $items.Count, $it.Name, $status, $it.Desc, $st) -ForegroundColor $(if ($it.AllowListed){'DarkGray'}else{'White'})
        # Always show the impact line so the user knows what ability is lost.
        if ($it.Impact) {
            Write-Host ("     impact: {0}" -f $it.Impact) -ForegroundColor $(if ($it.AllowListed){'DarkGray'}else{'Yellow'})
        }

        if ($it.AllowListed) { $index++; continue }

        if ($interactive -and -not $AssumeYes) {
            $key = $Host.UI.RawUI.ReadKey('IncludeKeyDown,NoEcho')
            $k = $key.Character.ToString().ToUpper()
            switch ($k) {
                'D' { $it.Action = 'Disabled' }
                'M' { $it.Action = 'Manual' }
                'A' { $it.Action = 'Auto' }
                'S' { $it.Action = $it.Default }
                'K' { $it.Action = $it.StartType.ToString() }
                default { $it.Action = $it.Default }
            }
        }
        # else: $it.Action is already the default, no per-item prompt

        # Apply if changed
        if ($it.Action -ne $it.StartType.ToString()) {
            # Set-Service -StartupType accepts the enum or its string name.
            # Avoid casting to [ServiceStartupType] because the type is in
            # System.ServiceProcess.dll which may not be loaded on minimal
            # PowerShell hosts (Nanoserver, WinPE, constrained language).
            $newType = $it.Action
            if ($DryRun) {
                Write-Info "DRY-RUN: Set-Service $($it.Name) -StartupType $newType"
                Add-Change $Module "service:$($it.Name)" $it.StartType $it.Action 'DRY'
            } else {
                try {
                    Set-Service -Name $it.Name -StartupType $newType -ErrorAction Stop
                    if ($newType -eq 'Disabled') { Stop-Service -Name $it.Name -Force -ErrorAction SilentlyContinue }
                    Add-Change $Module "service:$($it.Name)" $it.StartType $it.Action 'OK'
                } catch {
                    Write-Warn "  Failed: $($_.Exception.Message)"
                    Add-Change $Module "service:$($it.Name)" $it.StartType $it.Action 'ERR'
                }
            }
        } else {
            Add-Change $Module "service:$($it.Name)" $it.StartType 'unchanged' 'SKIP'
        }
        $index++
    }

    if ($snap) {
        Write-Pass "Service debloat complete. Snapshot: $snap"
        Write-Info "To rollback: run 'R' from main menu and pick this snapshot."
    } else {
        Write-Pass "Service debloat dry-run complete (no changes written, no snapshot taken)."
    }
}

