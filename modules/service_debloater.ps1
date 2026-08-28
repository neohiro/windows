# service_debloater.ps1 -- Interactive service debloater with allow-list + snapshot
$Module = 'service_debloater'

# Default catalog: service name -> friendly description. All settable to Manual or Disabled.
# User can choose Disable / Manual per row, with an A (apply to all) shortcut.
$DefaultServices = @(
    @{ Name='DiagTrack';                                  Desc='Connected User Experiences & Telemetry';  DefaultAction='Disabled' }
    @{ Name='dmwappushservice';                           Desc='WAPPushService (device metadata wireless)';DefaultAction='Disabled' }
    @{ Name='HomeGroupListener';                          Desc='HomeGroup Listener (Win10 only)';         DefaultAction='Disabled' }
    @{ Name='HomeGroupProvider';                          Desc='HomeGroup Provider (Win10 only)';         DefaultAction='Disabled' }
    @{ Name='lfsvc';                                      Desc='Geolocation Service';                     DefaultAction='Disabled' }
    @{ Name='MapsBroker';                                 Desc='Downloaded Maps Manager';                 DefaultAction='Disabled' }
    @{ Name='NetTcpPortSharing';                          Desc='Net.Tcp Port Sharing';                    DefaultAction='Disabled' }
    @{ Name='RemoteAccess';                               Desc='Routing and Remote Access';               DefaultAction='Disabled' }
    @{ Name='RemoteRegistry';                             Desc='Remote Registry';                         DefaultAction='Disabled' }
    @{ Name='RetailDemo';                                 Desc='Retail Demo Service';                     DefaultAction='Disabled' }
    @{ Name='SharedAccess';                               Desc='ICS (Internet Connection Sharing)';       DefaultAction='Disabled' }
    @{ Name='sshd';                                       Desc='OpenSSH Server';                          DefaultAction='Disabled' }
    @{ Name='TrkWks';                                     Desc='Distributed Link Tracking Client';        DefaultAction='Disabled' }
    @{ Name='WbioSrvc';                                   Desc='Windows Biometric Service';               DefaultAction='Manual' }
    @{ Name='WMPNetworkSvc';                              Desc='Windows Media Player network sharing';    DefaultAction='Disabled' }
    @{ Name='WerSvc';                                     Desc='Windows Error Reporting Service';         DefaultAction='Disabled' }
    @{ Name='XblAuthManager';                             Desc='Xbox Live Auth Manager';                  DefaultAction='Disabled' }
    @{ Name='XblGameSave';                                Desc='Xbox Live Game Save';                     DefaultAction='Disabled' }
    @{ Name='XboxGipSvc';                                 Desc='Xbox Accessory Management Service';       DefaultAction='Disabled' }
    @{ Name='XboxNetApiSvc';                              Desc='Xbox Live Networking Service';            DefaultAction='Disabled' }
    @{ Name='PrintSpooler';                               Desc='Print Spooler (PrintNightmare)';          DefaultAction='Disabled' }
    @{ Name='Fax';                                        Desc='Fax Service';                             DefaultAction='Disabled' }
    @{ Name='TabletInputService';                         Desc='Touch Keyboard & Handwriting Panel';     DefaultAction='Disabled' }
    @{ Name='WSearch';                                    Desc='Windows Search Indexer';                  DefaultAction='Manual' }
    @{ Name='SysMain';                                    Desc='SysMain (Superfetch)';                    DefaultAction='Manual' }
    @{ Name='CDPUserSvc';                                 Desc='Connected Devices Platform User';         DefaultAction='Disabled' }
    @{ Name='OneSyncSvc';                                 Desc='Sync Host (Mail/Calendar/People)';        DefaultAction='Disabled' }
    @{ Name='UnistoreSvc';                                Desc='User Data Storage';                       DefaultAction='Disabled' }
    @{ Name='PimIndexMaintenanceSvc';                     Desc='Contact Data';                            DefaultAction='Disabled' }
    @{ Name='BcastDVRUserService';                        Desc='GameDVR & Broadcast User Service';        DefaultAction='Disabled' }
    @{ Name='CaptureService';                             Desc='CaptureService (screenshots)';            DefaultAction='Disabled' }
    @{ Name='FrameServer';                                Desc='Camera Frame Server';                     DefaultAction='Disabled' }
    @{ Name='edgeupdate';                                 Desc='Edge Update Service (edgeupdate)';        DefaultAction='Manual' }
    @{ Name='edgeupdatem';                                Desc='Edge Update Service (edgeupdatem)';       DefaultAction='Manual' }
)

function Get-ServiceCatalog {
    return $DefaultServices
}

function Set-ServiceDebloater {
    param([bool]$DryRun, [array]$AllowList)
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
    }

    $index = 0
    while ($index -lt $items.Count) {
        $it = $items[$index]
        $status = if ($it.Status -eq 'Running') { '[running]' } else { '[stopped]' }
        $st = if ($it.AllowListed) { '[ALLOW-LISTED]' } else { "[$($it.StartType) -> $($it.Action)]" }

        Write-Host ""
        Write-Host ("[{0,2}/{1,-2}] {2}  ({3})  {4}  {5}" -f ($index+1), $items.Count, $it.Name, $status, $it.Desc, $st) -ForegroundColor $(if ($it.AllowListed){'DarkGray'}else{'White'})

        if ($it.AllowListed) { $index++; continue }

        if ($interactive) {
            $key = $Host.UI.RawUI.ReadKey('IncludeKeyDown,NoEcho')
            $k = $key.Character.ToString().ToUpper()
            switch ($k) {
                'D' { $it.Action = 'Disabled' }
                'M' { $it.Action = 'Manual' }
                'A' { $it.Action = 'Auto' }
                'S' { $it.Action = $it.Default }
                'K' { $it.Action = $it.StartType.ToString() }   # keep
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

