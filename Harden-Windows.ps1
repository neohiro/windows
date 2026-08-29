<#
.SYNOPSIS
    Harden-Windows.ps1 -- One-command Windows 10/11 hardening orchestrator.
.DESCRIPTION
    Loads modular hardening scripts, resolves allow-lists, presents interactive
    one-key menus, supports Dry-Run and Rollback. Designed to be launched
    via `harden.cmd` for maximum simplicity.
    Usage:
        .\Harden-Windows.ps1                    # interactive
        .\Harden-Windows.ps1 -Profile Home     # non-interactive preset
        .\Harden-Windows.ps1 -DryRun           # preview all changes
        .\Harden-Windows.ps1 -Rollback         # restore last snapshot
        .\Harden-Windows.ps1 -SkipDebloat      # skip interactive debloaters
        .\Harden-Windows.ps1 -AllowListOverride @{ Services=@('wuauserv') }
#>

[CmdletBinding()]
param(
    [ValidateSet('Home','Workstation','Developer','Custom','')]
    [string]$Profile = '',

    [switch]$DryRun,

    [switch]$Rollback,

    [switch]$SkipDebloat,

    [switch]$AssumeYes,

    [switch]$ConfirmImpact,

    [switch]$ValidateAllowList,

    [hashtable]$AllowListOverride = @{},

    [string]$ModulePath = "$PSScriptRoot\modules",

    [string]$ConfigPath = "$PSScriptRoot\config"
)

$ErrorActionPreference = 'Continue'

# Local polyfill for PowerShell 5.1 (which lacks the `??` null-coalescing operator).
# Defined at the top so the rest of the file can use Coalesce regardless of
# execution order.
if (-not (Test-Path Function:\Coalesce)) {
    function Coalesce { param($a, $b) if ($null -ne $a) { $a } else { $b } }
}

# --- Bootstrap --------------------------------------------------------------
. "$PSScriptRoot\lib\core.ps1"

# --- Validate allow-list and exit --------------------------------------------
# Runs even before admin check — no system modifications.
$script:ConfigDir = "$env:ProgramData\HardenWindows"

if ($ValidateAllowList) {
    $profileData = Import-PowerShellDataFile -Path "$ConfigPath\profiles.psd1" -ErrorAction SilentlyContinue
    $alFile = "$ConfigPath\default.AllowList.psd1"
    $alData = Import-PowerShellDataFile -Path $alFile -ErrorAction SilentlyContinue
    $runtimeAl = Get-AllowList

    if ($alData) {
        if ($alData.Services) {
            $runtimeAl.Services = @((Coalesce $runtimeAl.Services @()) + @($alData.Services)) | Select-Object -Unique
        }
        if ($alData.Appx) {
            $runtimeAl.Appx = @((Coalesce $runtimeAl.Appx @()) + @($alData.Appx)) | Select-Object -Unique
        }
        if ($alData.Modules) {
            $modules = $runtimeAl.Modules
            if ($null -eq $modules) { $modules = @{} }
            if ($modules -isnot [hashtable]) {
                $ht = @{}
                foreach ($p in $modules.PSObject.Properties) { $ht[$p.Name] = @($p.Value) }
                $modules = $ht
            }
            foreach ($mk in $alData.Modules.Keys) {
                $existing = @($modules[$mk])
                $modules[$mk] = @($existing + @($alData.Modules[$mk])) | Select-Object -Unique
            }
            $runtimeAl.Modules = $modules
        }
    }

    $validated = Test-AllowListSchema -Data $runtimeAl
    if ($validated.Ok) {
        $svcCount = @($runtimeAl.Services).Count
        $appxCount = @($runtimeAl.Appx).Count
        $modKeys = if ($runtimeAl.Modules -is [hashtable]) { $runtimeAl.Modules.Keys.Count } else { 0 }
        Write-Output "Allow-list is valid."
        Write-Output "  Services : $svcCount"
        Write-Output "  Appx     : $appxCount"
        Write-Output "  Modules  : $modKeys"
        exit 0
    } else {
        Write-Output "Allow-list has $($validated.Errors.Count) error(s):"
        foreach ($e in $validated.Errors) { Write-Warning $e }
        exit 1
    }
}

if (-not (Test-IsAdmin)) {
    Invoke-SelfElevate @PSBoundParameters
    return
}

if (-not (Test-WindowsVersion)) {
    Write-Warn "Requires Windows 10 1903+ or Windows 11."
    return
}

# --- Dry-run or rollback ---------------------------------------------------
if ($DryRun) {
    Write-Banner "DRY RUN -- No changes will be written"
}

# Rollback is the same operation whether invoked from the CLI (-Rollback) or
# from the menu ('R' key). Centralize the logic to avoid the two paths drifting
# apart over time.
function Invoke-LatestRollback {
    Initialize-Logging
    $snapshots = Get-ChildItem "$env:ProgramData\HardenWindows\State\snapshot-*\manifest.json" -ErrorAction SilentlyContinue
    if ($snapshots) {
        $latest = $snapshots | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Restore-Snapshot -ManifestPath $latest.FullName
    } else {
        Write-Warn "No snapshots found."
    }
    Close-Logging
}

if ($Rollback) {
    Invoke-LatestRollback
    return
}

# --- Init ------------------------------------------------------------------
Initialize-Logging
Write-Banner "Harden-Windows  |  neohiro/windows enhanced"

# One CIM query for the OS metadata that the banner prints; saves a round-trip
# to WMI per field.
$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$osCaption   = if ($osInfo) { $osInfo.Caption }     else { 'Unknown' }
$osBuild     = if ($osInfo) { $osInfo.BuildNumber } else { '?' }
Write-Host "Timestamp  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Admin     : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "OS        : $osCaption"
Write-Host "Build     : $osBuild"
Write-Host "Dry run   : $DryRun"
Write-Host ""

# Restore point. In non-interactive contexts (CI, piped input, hidden window)
# we must NOT silently create a system restore point — that would be a hidden
# filesystem action triggered without an explicit human decision. Default 'N'
# unless the operator is actually present at the keyboard.
if (-not $DryRun) {
    $restoreDefault = if (Test-IsInteractive) { 'Y' } else { 'N' }
    $resp = Invoke-TimedPrompt -Message "Create a system restore point before proceeding?" -Default $restoreDefault -ValidChars @('Y','N')
    if ($resp -eq 'Y') { New-SystemRestorePoint | Out-Null }
}

# --- Load config ------------------------------------------------------------
$profileData = Import-PowerShellDataFile -Path "$ConfigPath\profiles.psd1" -ErrorAction SilentlyContinue
$alFile = "$ConfigPath\default.AllowList.psd1"
$alData = Import-PowerShellDataFile -Path $alFile -ErrorAction SilentlyContinue
$runtimeAl = Get-AllowList

# Merge the source-controlled default.AllowList.psd1 into runtime allow-list
# (priority: CLI override > runtime JSON > .psd1 default)
if ($alData) {
    if ($alData.Services) {
        $runtimeAl.Services = @(Coalesce $runtimeAl.Services @()) + @($alData.Services) | Select-Object -Unique
    }
    if ($alData.Appx) {
        $runtimeAl.Appx = @(Coalesce $runtimeAl.Appx @()) + @($alData.Appx) | Select-Object -Unique
    }
    if ($alData.Modules) {
        $modules = $runtimeAl.Modules
        if ($null -eq $modules) { $modules = @{} }
        if ($modules -isnot [hashtable]) {
            # Convert from PSCustomObject to hashtable for uniform merging
            $ht = @{}
            foreach ($p in $modules.PSObject.Properties) { $ht[$p.Name] = @($p.Value) }
            $modules = $ht
        }
        foreach ($mk in $alData.Modules.Keys) {
            $existing = @($modules[$mk])
            $modules[$mk] = @($existing + @($alData.Modules[$mk])) | Select-Object -Unique
        }
        $runtimeAl.Modules = $modules
    }
}

if ($AllowListOverride.Services) {
    $runtimeAl.Services = @(Coalesce $runtimeAl.Services @()) + @($AllowListOverride.Services) | Select-Object -Unique
}
if ($AllowListOverride.Appx) {
    $runtimeAl.Appx = @(Coalesce $runtimeAl.Appx @()) + @($AllowListOverride.Appx) | Select-Object -Unique
}

# Merge module-level allow-lists. $runtimeAl.Modules has been normalized to a
# hashtable when the .psd1 Modules branch ran; if no .psd1 Modules were given,
# it may still be a PSCustomObject (@{} serialized as JSON). Handle both.
# Flatten to a clean string array: hashtable keys are module-name strings and
# hashtable values are string arrays; both need to be included.
$allAllowList = @($runtimeAl.Services | Where-Object { $_ -is [string] -and $_ })
if ($null -ne $runtimeAl.Modules) {
    if ($runtimeAl.Modules -is [hashtable]) {
        $allAllowList += $runtimeAl.Modules.Keys
        foreach ($v in $runtimeAl.Modules.Values) {
            if ($v -is [string])      { $allAllowList += $v }
            elseif ($v -is [array])    { $allAllowList += $v }
        }
    } elseif ($runtimeAl.Modules.PSObject) {
        $allAllowList += $runtimeAl.Modules.PSObject.Properties.Name
        $allAllowList += $runtimeAl.Modules.PSObject.Properties.Value | ForEach-Object {
            if ($_ -is [string])      { $_ }
            elseif ($_ -is [array])   { $_ }
        }
    }
}
# Deduplicate so a name appearing in both Services and Modules is only listed once.
$allAllowList = @($allAllowList | Select-Object -Unique)

# --- Load all module functions ------------------------------------------------
$moduleFiles = Get-ChildItem -Path $ModulePath -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($mf in $moduleFiles) {
    try {
        . $mf.FullName
    } catch {
        Write-Warn "Module load failed: $($mf.Name) -- $_"
    }
}

# --- Determine what to run --------------------------------------------------
if (-not $Profile -or $Profile -eq 'Custom') {
    if (-not (Test-IsInteractive)) {
        # No usable console. Default to Home profile with a notice rather than hanging
        # on ReadKey forever. Users wanting a different profile must pass -Profile.
        Write-Info "Non-interactive context detected; defaulting to Home profile. Use -Profile to override."
        $Profile = 'Home'
    } else {
        Show-MainMenu
        $ch = $Host.UI.RawUI.ReadKey('IncludeKeyDown,NoEcho')
        $ch = $ch.Character.ToString().ToUpper()

        switch ($ch) {
            '1' { $Profile = 'Home';       Write-Host "Profile: HOME" -ForegroundColor Green }
            '2' { $Profile = 'Workstation'; Write-Host "Profile: WORKSTATION" -ForegroundColor Green }
            '3' { $Profile = 'Developer'; Write-Host "Profile: DEVELOPER" -ForegroundColor Green }
            '4' {
                Write-Host "Custom module selection:" -ForegroundColor Cyan
                $allModules = Get-ChildItem $ModulePath -Name -ErrorAction SilentlyContinue | Where-Object { $_ -notlike '_*' }
                foreach ($m in $allModules) { Write-Host "  - $m" }
                $Profile = 'Home'
            }
            'D' {
                $DryRun = $true
                Write-Host "Dry run mode" -ForegroundColor Yellow
                $Profile = 'Home'
            }
            'R' { Invoke-LatestRollback; return }
            'Q' { Write-Host "Exiting." -ForegroundColor DarkGray; return }
            default { $Profile = 'Home' }
        }
    }
}

if ($profileData -and $profileData[$Profile]) {
    $selectedModules = $profileData[$Profile].Modules
    $skippedModules  = $profileData[$Profile].Skip
} else {
    $selectedModules = @(
        'core','defender','firewall','smb_network','account_lockout',
        'usb_autoplay','powershell_logging','audit_logging',
        'browser','office','privacy','fileassoc','biometrics',
        'powershell_v2','optional_features','backup_recovery'
    )
    if (-not $SkipDebloat) {
        $selectedModules += 'service_debloater','appx_debloater'
    }
    $skippedModules = @()
}

# --- Snapshot before --------------------------------------------------------
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $DryRun) {
    $preSnap = New-Snapshot -Label "pre-hardening-$timestamp"
    Write-Info "Pre-snapshot: $preSnap"
}

# --- Run modules -----------------------------------------------------------
# Map module name to its Set-* function. Single source of truth: any new
# module must add its entry here AND define the corresponding function in
# the module file. The regression suite verifies the mapping is complete.
# Hoisted out of the per-module loop so it isn't rebuilt for every module.
$fnMap = @{
    'core'                = 'Set-CoreSettings'
    'defender'            = 'Set-DefenderSettings'
    'firewall'            = 'Set-FirewallSettings'
    'smb_network'         = 'Set-SmbNetworkSettings'
    'account_lockout'     = 'Set-AccountLockoutSettings'
    'usb_autoplay'        = 'Set-UsbAutoplaySettings'
    'powershell_logging'  = 'Set-PowerShellLogging'
    'audit_logging'       = 'Set-AuditLogging'
    'browser'             = 'Set-BrowserSettings'
    'office'              = 'Set-OfficeSettings'
    'privacy'             = 'Set-PrivacySettings'
    'fileassoc'           = 'Set-FileAssocSettings'
    'biometrics'          = 'Set-BiometricsSettings'
    'powershell_v2'       = 'Set-PowerShellV2'
    'optional_features'   = 'Set-OptionalFeatures'
    'backup_recovery'     = 'Set-BackupRecovery'
    'service_debloater'   = 'Set-ServiceDebloater'
    'appx_debloater'      = 'Set-AppxDebloater'
}

Write-Host ""
Write-Host "Running modules: $($selectedModules.Count)" -ForegroundColor Cyan
Write-Host ""

$interactiveModules = @('service_debloater','appx_debloater','usb_autoplay','fileassoc')
$skipInteractive = $DryRun

foreach ($modName in $selectedModules) {
    if ($modName -in $skippedModules) {
        Write-Skip "Module skipped by profile: $modName"
        continue
    }
    if ($modName -in $interactiveModules -and $skipInteractive) {
        Write-Info "Skipping interactive module (dry-run): $modName"
        continue
    }

    $fnName = $fnMap[$modName]
    if (-not $fnName) { Write-Warn "Unknown module (not in fnMap): $modName"; continue }

    Write-Section "Module: $modName"
    if (Get-Command $fnName -ErrorAction SilentlyContinue) {
        try {
            if ($modName -eq 'appx_debloater') {
                & $fnName -DryRun $DryRun -AllowList $allAllowList -AssumeYes:$AssumeYes
            } else {
                & $fnName -DryRun $DryRun -AllowList $allAllowList -AssumeYes:$AssumeYes -ConfirmImpact:$ConfirmImpact
            }
        } catch {
            Write-Warn "Module error [$modName]: $($_.Exception.Message)"
            Add-Change $modName 'module' '?' 'error' 'ERR'
        }
    } else {
        Write-Warn "Function '$fnName' not found in module: $modName"
    }
}

# --- Summary ---------------------------------------------------------------
Write-Host ""
Write-Banner "Results"
# $Script:Changes may be null if Initialize-Logging failed before $Script:Changes
# was initialized (e.g. transcript path was unwritable). Guard the pipeline.
$changes = if ($null -eq $Script:Changes) { @() } else { @($Script:Changes) }
$ok    = $changes | Where-Object { $_.Status -eq 'OK' }
$skip  = $changes | Where-Object { $_.Status -eq 'SKIP' }
$err   = $changes | Where-Object { $_.Status -eq 'ERR' }
$dry   = $changes | Where-Object { $_.Status -eq 'DRY' }

Write-Host "Applied   : $(@($ok).Count)" -ForegroundColor Green
Write-Host "Skipped   : $(@($skip).Count)" -ForegroundColor DarkGray
Write-Host "Errors    : $(@($err).Count)" -ForegroundColor Red
Write-Host "Dry-run   : $(@($dry).Count)" -ForegroundColor Yellow
Write-Host "Total     : $(@($changes).Count)"

Close-Logging

if (-not $DryRun) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "REBOOT REQUIRED for many changes to take effect." -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Cyan
    $r = Invoke-TimedPrompt -Message "Reboot now?" -Default 'N' -ValidChars @('Y','N')
    if ($r -eq 'Y') { Restart-Computer -Force } else { Write-Host "Reboot postponed. Run 'shutdown /r /t 0' when ready." -ForegroundColor Yellow }
} else {
    Write-Host ""
    Write-Host "Dry run complete. Run without -DryRun to apply." -ForegroundColor Yellow
}
