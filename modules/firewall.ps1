# firewall.ps1 -- Windows Firewall hardening: profiles, logging, LOLBin outbound blocks
$Module = 'firewall'

$Lolbins = @(
    'notepad.exe','regsvr32.exe','calc.exe','mshta.exe',
    'wscript.exe','cscript.exe','runscripthelper.exe','hh.exe'
)

# Hoisted helper: runs a netsh command via cmd /c so the command line is
# always passed to the native netsh.exe without PowerShell parsing quirks
# (notably the /c and quoting of the rule-name argument).
function Invoke-Netsh {
    param([string]$Args, [bool]$DryRun)
    if ($DryRun) { Write-Info "DRY-RUN: netsh $Args"; return }
    try {
        $null = cmd /c "netsh $Args 2>NUL"
    } catch {
        Write-Warn "netsh $Args failed: $($_.Exception.Message)"
    }
}

function Set-FirewallSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Windows Firewall"

    Invoke-Netsh -Args 'advfirewall set allprofiles state on' -DryRun $DryRun

    Invoke-Netsh -Args 'advfirewall set currentprofile logging filename %systemroot%\system32\LogFiles\Firewall\pfirewall.log' -DryRun $DryRun
    Invoke-Netsh -Args 'advfirewall set currentprofile logging maxfilesize 4096' -DryRun $DryRun
    Invoke-Netsh -Args 'advfirewall set currentprofile logging droppedconnections enable' -DryRun $DryRun
    Invoke-Netsh -Args 'advfirewall set publicprofile firewallpolicy blockinboundalways,allowoutbound' -DryRun $DryRun

    foreach ($bin in $Lolbins) {
        $name = "Block $bin netconns"
        $ruleName = "Block$(($bin -split '\.')[0])Exe"
        if ($AllowList -contains $ruleName) {
            Write-Skip "Firewall rule allow-listed: $name"
            Add-Change $Module "rule:$name" 'would block' 'ALLOWED' 'SKIP'
            continue
        }
        if (-not $DryRun) {
            cmd /c "netsh advfirewall firewall delete rule name=`"$name`" 2>NUL" | Out-Null
        }
        Invoke-Netsh -Args "advfirewall firewall add rule name=`"$name`" program=`"%systemroot%\system32\$bin`" protocol=tcp dir=out enable=yes action=block profile=any" -DryRun $DryRun
        Add-Change $Module "rule:$name" 'unset' 'blocked' $(if($DryRun){'DRY'}else{'OK'})
    }

    Write-Pass "Firewall profile + LOLBin blocks applied."
}

