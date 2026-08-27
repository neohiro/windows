# firewall.ps1 -- Windows Firewall hardening: profiles, logging, LOLBin outbound blocks
$Module = 'firewall'

$Lolbins = @(
    'notepad.exe','regsvr32.exe','calc.exe','mshta.exe',
    'wscript.exe','cscript.exe','runscripthelper.exe','hh.exe'
)

function Set-FirewallSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Windows Firewall"

    # Helper: run a netsh command, handling DryRun vs real execution cleanly.
    function Invoke-Netsh {
        param([string]$Args)
        if ($DryRun) { Write-Info "DRY-RUN: netsh $Args" }
        else {
            try {
                # Run via cmd /c to handle netsh syntax correctly in all PS environments
                $null = cmd /c "netsh $Args 2>NUL"
            } catch {
                Write-Warn "netsh $Args failed: $_"
            }
        }
    }

    Invoke-Netsh 'advfirewall set allprofiles state on'

    Invoke-Netsh 'advfirewall set currentprofile logging filename %systemroot%\system32\LogFiles\Firewall\pfirewall.log'
    Invoke-Netsh 'advfirewall set currentprofile logging maxfilesize 4096'
    Invoke-Netsh 'advfirewall set currentprofile logging droppedconnections enable'
    Invoke-Netsh 'advfirewall set publicprofile firewallpolicy blockinboundalways,allowoutbound'

    foreach ($bin in $Lolbins) {
        $name = "Block $bin netconns"
        $ruleName = "Block$(($bin -split '\.')[0])Exe"
        if ($AllowList -contains $ruleName) {
            Write-Skip "Firewall rule allow-listed: $name"
            Add-Change $Module "rule:$name" 'would block' 'ALLOWED' 'SKIP'
            continue
        }
        if (-not $DryRun) {
            cmd /c "netsh advfirewall firewall delete rule name=`"$name`" 2>NUL"
        }
        Invoke-Netsh "advfirewall firewall add rule name=`"$name`" program=`"%systemroot%\system32\$bin`" protocol=tcp dir=out enable=yes action=block profile=any"
        Add-Change $Module "rule:$name" 'unset' 'blocked' $(if($DryRun){'DRY'}else{'OK'})
    }

    Write-Pass "Firewall profile + LOLBin blocks applied."
}

