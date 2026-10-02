# Harden-Windows - Library
# Core utilities: Prerequisite checks, UI helpers, logging, rollback, allow-list

$Script:LogDir    = "$env:ProgramData\HardenWindows\Logs"
$Script:StateDir  = "$env:ProgramData\HardenWindows\State"
$Script:ConfigDir = "$env:ProgramData\HardenWindows\Config"
$Script:Changes   = [System.Collections.Generic.List[object]]::new()

# Centralized prompt timeouts so callers don't pass magic numbers and so
# the security-sensitive confirm prompt is easy to audit.
$Script:PromptTimeoutSeconds    = 15   # standard y/n prompts
$Script:HighImpactTimeoutSeconds = 60  # typed "Yes"/"yes" confirmation

# ----------------------------------------------
# Self-elevate if not admin
# ----------------------------------------------
function Invoke-SelfElevate {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Forward only serializable scalar arguments to avoid shell-arg quoting issues
        # (hashtables like AllowListOverride cannot be safely embedded in -ArgumentList).
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$PSCommandPath`"")
        if ($Profile)      { $argList += "-Profile `"$Profile`"" }
        if ($DryRun)       { $argList += '-DryRun' }
        if ($SkipDebloat)  { $argList += '-SkipDebloat' }
        if ($Rollback)     { $argList += '-Rollback' }
        if ($AssumeYes)    { $argList += '-AssumeYes' }
        if ($ConfirmImpact)  { $argList += '-ConfirmImpact' }
        if ($ValidateAllowList) { $argList += '-ValidateAllowList' }
        # Forward custom paths so a user who runs `.\Harden-Windows.ps1 -ConfigPath D:\my-config`
        # still gets the same paths after elevation.
        if ($ConfigPath)   { $argList += "-ConfigPath `"$ConfigPath`"" }
        if ($ModulePath)   { $argList += "-ModulePath `"$ModulePath`"" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit
    }
}

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WindowsVersion {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    } catch {
        Write-Warn "Get-CimInstance failed (WinRM/CIM may be unavailable): $($_.Exception.Message)"
        return $false
    }
    if ($os.Caption -match 'Windows 1[01]' -or $os.BuildNumber -ge 10240) { return $true }
    return $false
}

function Get-ErrorContext {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    $loc = $ErrorRecord.InvocationInfo
    $script = if ($loc.ScriptName) { Split-Path $loc.ScriptName -Leaf } else { '<console>' }
    $line   = if ($null -ne $loc.ScriptLineNumber) { $loc.ScriptLineNumber } else { '?' }
    $fn     = if ($loc.MyCommand) { $loc.MyCommand.Name } else { '' }
    $ctx = "at ${script}:${line}"
    if ($fn) { $ctx += " [$fn]" }
    return $ctx
}

function Write-RuntimeError {
    param(
        [string]$Phase,
        [string]$Message,
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    $ctx = if ($ErrorRecord) { Get-ErrorContext $ErrorRecord } else { '' }
    Write-Host "[!!] [$Phase] $Message" -ForegroundColor Red
    if ($ctx)       { Write-Host "       $ctx"       -ForegroundColor Red }
    if ($ErrorRecord -and $ErrorRecord.Exception) {
        Write-Host "       Exception: $($ErrorRecord.Exception.Message)" -ForegroundColor DarkGray
    }
}

function Invoke-WithErrorFeedback {
    param(
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Description,
        [scriptblock]$Action
    )
    try {
        $result = & $Action
        return $result
    } catch {
        Write-RuntimeError -Phase $Phase -Message "FAILED: $Description" -ErrorRecord $_
        return $null
    }
}

# ----------------------------------------------
# Coloured output
# ----------------------------------------------
function Write-Banner {
    param([string]$Text)
    $len = $Text.Length + 4
    Write-Host ""
    Write-Host ("#" * $len) -ForegroundColor Cyan
    Write-Host "# $Text" -ForegroundColor Cyan
    Write-Host ("#" * $len) -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host ("[>>] $Text") -ForegroundColor Yellow
}

function Write-Pass {
    param([string]$Text)
    Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "[!!] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "[ii] $Text" -ForegroundColor DarkGray
}

function Write-Skip {
    param([string]$Text)
    Write-Host "[--] $Text" -ForegroundColor DarkGray
}

# ----------------------------------------------
# Logging & transcripts
# ----------------------------------------------
function Initialize-Logging {
    $null = New-Item -ItemType Directory -Force -Path $Script:LogDir
    $null = New-Item -ItemType Directory -Force -Path $Script:StateDir
    $null = New-Item -ItemType Directory -Force -Path $Script:ConfigDir

    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $Script:TranscriptPath = "$Script:LogDir\harden-$ts.log"
    $Script:ChangeLogPath  = "$Script:LogDir\changes-$ts.json"
    if ($null -eq $Script:Changes) {
        $Script:Changes = [System.Collections.Generic.List[object]]::new()
    }

    # Stop any transcript the host or parent session has running, then start ours.
    # Without this guard, Start-Transcript throws "transcript already running" and
    # $Script:TranscriptPath stays null, causing Close-Logging to fail.
    # ServerRemoteHost doesn't support Stop-Transcript, so guard the call.
    if ($Host.Name -ne 'ServerRemoteHost') {
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    try {
        Start-Transcript -Path $Script:TranscriptPath -Append -ErrorAction Stop | Out-Null
    } catch {
        # Last-ditch: log to a file we own, no transcript
        Write-Host "[!!] Start-Transcript failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[!!] Transcript logging disabled; changes will still be written to $($Script:ChangeLogPath)" -ForegroundColor Yellow
        $Script:TranscriptPath = $null
    }
}

function Add-Change {
    param([string]$Module, [string]$Setting, [string]$OldValue, [string]$NewValue, [string]$Status)
    if ($null -eq $Script:Changes) {
        $Script:Changes = [System.Collections.Generic.List[object]]::new()
    }
    # Use Add() for O(1) append. Direct .Add on the list avoids the O(n)
    # array-realloc penalty of `$arr += $obj` on large run logs.
    $Script:Changes.Add([PSCustomObject]@{
        Timestamp = (Get-Date).ToString("o")
        Module    = $Module
        Setting   = $Setting
        OldValue  = $OldValue
        NewValue  = $NewValue
        Status    = $Status
    }) | Out-Null
}

function Close-Logging {
    $changeLogWritten = $false
    if ($Script:Changes -and $Script:ChangeLogPath) {
        try {
            [System.IO.File]::WriteAllText(
                $Script:ChangeLogPath,
                ($Script:Changes | ConvertTo-Json -Depth 5),
                [System.Text.Encoding]::UTF8
            )
            $changeLogWritten = $true
        } catch {
            Write-Host "[!!] Failed to write change log: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    if ($Script:TranscriptPath) {
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    Write-Host ""
    if ($Script:TranscriptPath) { Write-Host "Transcript : $Script:TranscriptPath" -ForegroundColor DarkGray }
    if ($changeLogWritten)      { Write-Host "Change log : $Script:ChangeLogPath"   -ForegroundColor DarkGray }
}

# ----------------------------------------------
# Interactive one-key menus
# ----------------------------------------------
function Show-MainMenu {
    $title = @"

#============================================================
#          HARDEN-WINDOWS  |  One-command hardening
#============================================================
#
#  Profile presets:
#    [1] Home     - Privacy + security, safe defaults
#    [2] Workstation - Hardened office workstation (STIG-lite)
#    [3] Developer - Extra allowed (PS remoting, dev tools)
#    [4] Custom   - Choose every module individually
#    [D] Dry run  - Preview changes without applying
#    [R] Rollback - Restore last session's changes
#    [Q] Quit
#
#  Allow-list: Edit  $Script:ConfigDir\allowlist.json
#
#============================================================
"@
    Write-Host $title -ForegroundColor Cyan
}

function Test-IsInteractive {
    # Returns $false when there is no usable console: stdin redirected (file/pipeline),
    # ServerRemoteHost, or -WindowStyle Hidden from Task Scheduler.
    # Do NOT call ReadKey here — it consumes a key from the buffer.
    try {
        if (-not [Environment]::UserInteractive) { return $false }
        if ($Host.Name -eq 'ServerRemoteHost')   { return $false }
        # [Console]::IsInputRedirected is $true when stdin is piped or redirected
        if ([Console]::IsInputRedirected)       { return $false }
        return $true
    } catch { return $false }
}

function Invoke-TimedPrompt {
    param(
        [string]$Message,
        [int]$TimeoutSeconds = $Script:PromptTimeoutSeconds,
        [string]$Default = "N",
        [char[]]$ValidChars = @('Y','N','S')
    )
    # Non-interactive context: never block. Use the default.
    if (-not (Test-IsInteractive)) { return $Default.ToUpper() }
    Write-Host "$Message [$Default] " -NoNewline -ForegroundColor Yellow

    # Poll for a keypress in a background thread, returning either the captured
    # character or $null when the timer fires. Using ReadKey directly would
    # block indefinitely on stdin in some hosts; the poll loop guarantees a
    # bounded wait that honours $TimeoutSeconds.
    $key = $null
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($Host.UI.RawUI.KeyAvailable) {
            $resp = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $key = $resp.Character
            break
        }
        Start-Sleep -Milliseconds 50
    }
    Write-Host ""

    if ($null -ne $key -and $key -in $ValidChars) { return $key.ToString().ToUpper() }
    return $Default.ToUpper()
}

# ----------------------------------------------
# Rollback engine
# ----------------------------------------------
function New-Snapshot {
    param([string]$Label)
    # Use millisecond precision + a short random suffix to eliminate collision
    # under fast repeated calls (e.g. service_debloater's pre-snapshot loop).
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $attempt = 0
    $maxAttempts = 8
    while ($true) {
        $suffix  = -join ((Get-Random -Count 8 -InputObject ([char[]]'0123456789abcdef')))
        $snapDir = "$Script:StateDir\snapshot-$Label-$stamp-$suffix"
        $attempt++
        try {
            $null = New-Item -ItemType Directory -Path $snapDir -ErrorAction Stop
            break  # success
        } catch {
            $inner = $_.Exception.InnerException
            $errCode = if ($null -ne $inner) { $inner.HResult } else { $null }
            # 0xB7 = ERROR_ALREADY_EXISTS (collisions on rapid same-second calls).
            # Anything else (permission denied, disk full, path too long) is fatal.
            if ($errCode -ne 0xB7 -and $errCode -ne 183) {
                throw "Cannot create snapshot directory '$snapDir': $($_.Exception.Message)"
            }
            if ($attempt -ge $maxAttempts) { throw "Snapshot directory collision after $maxAttempts attempts: $snapDir" }
            Start-Sleep -Milliseconds (Get-Random -Minimum 1 -Maximum 50)
        }
    }

    # Registry: export key hardening hives via reg.exe (preserves the real value format)
    $hives = @{
        'HKLM\SOFTWARE\Policies\Microsoft\Windows'                       = 'policies-windows.reg'
        'HKLM\SYSTEM\CurrentControlSet\Services'                         = 'services-hive.reg'
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'        = 'policies-currentversion.reg'
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'  = 'policies-system.reg'
        'HKLM\SOFTWARE\Policies\Microsoft\Windows NT'                    = 'policies-nt.reg'
    }
    $regIndex = @()
    foreach ($h in $hives.Keys) {
        $file = Join-Path $snapDir $hives[$h]
        $null = Invoke-WithErrorFeedback -Phase 'snapshot:reg-export' -Description "Export registry hive '$h'" -Action {
            $output = @(& reg export $h $file /y 2>&1)
            $exit = $LASTEXITCODE
            if ($exit -ne 0 -and $exit -ne 1) {
                throw "reg export exited $exit : $($output -join ' ')"
            }
        }
        if ((Test-Path $file) -and ((Get-Item $file).Length -gt 0)) {
            $regIndex += @{ Key = $h; File = $file }
        } else {
            Remove-Item $file -Force -ErrorAction SilentlyContinue
        }
    }

    # Services: real values
    $svcPath = Join-Path $snapDir 'services.json'
    try {
        [System.IO.File]::WriteAllText($svcPath,
            (Get-Service | Select-Object Name, Status, StartType | ConvertTo-Json -Depth 3),
            [System.Text.Encoding]::UTF8)
    } catch {
        throw "Failed to write services snapshot ($svcPath): $($_.Exception.Message)"
    }

    # Appx: capture Name, FullName, InstallLocation, Provisioned flag, and
    # DisplayName for provisioned packages. Restore-Snapshot uses this to
    # re-register user packages and warn about provisioned ones (which need
    # install media the user must supply).
    $appxPath = Join-Path $snapDir 'appx.json'
    $appxRecords = @()
    try {
        foreach ($p in (@(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue))) {
            $appxRecords += [PSCustomObject]@{
                Name            = $p.Name
                PackageFullName = $p.PackageFullName
                InstallLocation = $p.InstallLocation
                Provisioned     = $false
            }
        }
    } catch {
        Write-Warn "Get-AppxPackage during snapshot failed: $($_.Exception.Message)"
    }
    try {
        $provPkgs = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
        foreach ($p in $provPkgs) {
            $appxRecords += [PSCustomObject]@{
                Name            = $p.DisplayName
                PackageFullName = $p.PackageName
                InstallLocation = $null
                Provisioned     = $true
            }
        }
    } catch {
        Write-Warn "Get-AppxProvisionedPackage during snapshot failed: $($_.Exception.Message)"
    }
    try {
        [System.IO.File]::WriteAllText($appxPath, ($appxRecords | ConvertTo-Json -Depth 4), [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warn "Failed to write appx snapshot ($appxPath): $($_.Exception.Message)"
    }

    # Manifest: must be written last so Restore-Snapshot can rely on it as the
    # integrity gate (if the manifest is absent or corrupt, restore bails early).
    $manifest = @{
        Timestamp = (Get-Date).ToString("o")
        Label     = $Label
        RegFiles  = $regIndex
        Services  = $svcPath
        Appx      = $appxPath
    }
    $manifestPath = Join-Path $snapDir 'manifest.json'
    try {
        [System.IO.File]::WriteAllText($manifestPath,
            ($manifest | ConvertTo-Json -Depth 5),
            [System.Text.Encoding]::UTF8)
    } catch {
        throw "Failed to write snapshot manifest ($manifestPath): $($_.Exception.Message)"
    }
    return $manifestPath
}

function Restore-Snapshot {
    param([string]$ManifestPath)
    if (-not (Test-Path $ManifestPath)) { Write-Warn "Snapshot not found: $ManifestPath"; return }

    Write-Section "Rolling back from snapshot..."
    $snap = Get-Content $ManifestPath -Raw | ConvertFrom-Json

    # Services: only restore those whose start type differs from the snapshot.
    # A blanket restore of all services would spam change log entries for
    # services that weren't touched, and might restart services the user
    # intentionally stopped between snapshot and now.
    $svcRestored = 0
    $svcFailed   = 0
    if ($snap.Services -and (Test-Path $snap.Services)) {
        $svcData  = @(Get-Content $snap.Services -Raw | ConvertFrom-Json)
    # Build a Name -> service hashtable for O(1) lookup.
        $current = @{}
        try {
            foreach ($svc in Get-Service -ErrorAction Stop) { $current[$svc.Name] = $svc }
        } catch {
            Write-Warn "Get-Service failed during rollback: $($_.Exception.Message). Skipping service restore."
            $current = @{}
        }
        foreach ($s in $svcData) {
            $cur = $current[$s.Name]
            if (-not $cur) { continue }  # service not installed anymore
            try {
                $needsChange = $false
                if ($cur.StartType -ne $s.StartType) {
                    Set-Service -Name $s.Name -StartupType $s.StartType -ErrorAction Stop
                    $needsChange = $true
                }
                if ($s.Status -eq 'Running' -and $cur.Status -ne 'Running') {
                    Start-Service $s.Name -ErrorAction SilentlyContinue
                    $needsChange = $true
                } elseif ($s.Status -ne 'Running' -and $cur.Status -eq 'Running') {
                    Stop-Service $s.Name -Force -ErrorAction SilentlyContinue
                    $needsChange = $true
                }
                if ($needsChange) {
                    Add-Change "rollback" "service:$($s.Name)" 'modified' 'restored' 'OK'
                    $svcRestored++
                }
            } catch {
                Add-Change "rollback" "service:$($s.Name)" 'modified' 'failed' 'ERR'
                $svcFailed++
            }
        }
    }
    Write-Info "Services: $svcRestored restored, $svcFailed failed"

    # Registry: import each .reg file (reg.exe handles the format natively and idempotently)
    $regRestored = 0
    $regFailed   = 0
    foreach ($rf in $snap.RegFiles) {
        if (Test-Path $rf.File) {
            $out = reg import $rf.File 2>&1
            if ($LASTEXITCODE -eq 0) {
                Add-Change "rollback" "reg:$($rf.Key)" 'modified' 'imported' 'OK'
                $regRestored++
            } else {
                Add-Change "rollback" "reg:$($rf.Key)" 'modified' 'import-failed' 'ERR'
                Write-Warn "reg import failed: $($rf.Key)"
                $regFailed++
            }
        }
    }
    Write-Info "Registry : $regRestored hives restored, $regFailed failed"

    # Appx: re-register user packages from their on-disk InstallLocation.
    # Provisioned packages require install media the user must supply.
    $appxRestored = 0
    $appxSkipped  = 0
    $appxFailed   = 0
    $appxManual   = @()
    if ($snap.Appx -and (Test-Path $snap.Appx)) {
        $snapAppx = @(Get-Content $snap.Appx -Raw | ConvertFrom-Json)
        $currentNames = @{}
        foreach ($p in (Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
            $currentNames[$p.PackageFullName] = $true
        }
        foreach ($rec in $snapAppx) {
            if ($currentNames[$rec.PackageFullName]) { continue }
            if ([bool]$rec.Provisioned) {
                $appxManual += $rec.Name
                continue
            }
            if ([string]::IsNullOrWhiteSpace($rec.InstallLocation) -or -not (Test-Path $rec.InstallLocation)) {
                $appxManual += $rec.Name
                continue
            }
            try {
                $appxManifest = Join-Path $rec.InstallLocation 'AppxManifest.xml'
                if (-not (Test-Path $appxManifest)) {
                    $appxManual += $rec.Name
                    $appxSkipped++
                    continue
                }
                Add-AppxPackage -Register $appxManifest -ErrorAction Stop | Out-Null
                Add-Change "rollback" "appx:$($rec.Name)" 'removed' 're-registered' 'OK'
                $appxRestored++
            } catch {
                Add-Change "rollback" "appx:$($rec.Name)" 'removed' 're-register-failed' 'ERR'
                Write-Warn "  Failed to re-register $($rec.Name): $($_.Exception.Message)"
                $appxFailed++
            }
        }
        if ($appxManual.Count -gt 0) {
            $appxManual = @($appxManual | Select-Object -Unique)
            Write-Warn "The following Appx packages were removed but cannot be auto-restored."
            Write-Warn "Reinstall them from the Microsoft Store or with 'Add-AppxPackage':"
            foreach ($n in $appxManual) { Write-Host "  - $n" -ForegroundColor Yellow }
        }
    }
    Write-Info "Appx     : $appxRestored re-registered, $appxSkipped skipped (no media), $appxFailed failed, $($appxManual.Count) require manual reinstall"
    Write-Pass "Rollback complete. Reboot recommended for service + driver changes."
}

function New-SystemRestorePoint {
    $desc = "HardenWindows_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $desc -RestorePointType "MODIFY_SETTINGS"
        Write-Pass "Restore point created: $desc"
        return $true
    } catch {
        Write-Warn "Could not create restore point (requires admin + system protection enabled)."
        return $false
    }
}

# ----------------------------------------------
# Allow-list management
# ----------------------------------------------
function Get-AllowList {
    $path = "$Script:ConfigDir\allowlist.json"
    $default = [PSCustomObject]@{ Services = @(); Appx = @(); Modules = @{} }
    if (-not $path -or $path -eq '\allowlist.json') {
        Write-Warn "ConfigDir not initialized; allow-list path is empty. Using empty default."
        return $default
    }
    if (Test-Path $path) {
        try {
            $content = Get-Content $path -Raw
            if ([string]::IsNullOrWhiteSpace($content)) { return $default }
            $parsed = $content | ConvertFrom-Json
            if ($null -eq $parsed) { return $default }
            $validated = Test-AllowListSchema -Data $parsed -Path $path
            if (-not $validated.Ok) {
                # Test-AllowListSchema has already printed warnings for each issue.
                # Return a clean default so the user can still run harden, with the
                # understanding that their customizations were not applied.
                Write-Warn "Falling back to empty allow-list. Edit $path to fix the errors above."
                return $default
            }
            return $parsed
        } catch {
            # Corrupt JSON. Surface a warning so the user knows to fix the file.
            Write-Warn "allowlist.json at $path is not valid JSON: $($_.Exception.Message)"
            Write-Warn "Using empty default allow-list. Edit the file to restore."
            return $default
        }
    }
    return $default
}

function Set-AllowList {
    param([object]$Data)
    $path = "$Script:ConfigDir\allowlist.json"
    if (-not $path -or $path -eq '\allowlist.json') {
        Write-Warn "ConfigDir not initialized; cannot write allow-list. Aborting write."
        return
    }
    [System.IO.File]::WriteAllText($path, ($Data | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
}

# Validate the structure of an allow-list object as returned by ConvertFrom-Json.
# Returns a PSCustomObject { Ok = $true/$false; Errors = @('...') } so the
# caller can both surface individual problems and decide whether to fall back.
# Each Services/Appx entry must be a non-empty string. Each Modules entry
# must be a string key whose value is a string or array of strings.
function Test-AllowListSchema {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Data,
        [string]$Path = '<memory>'
    )
    $errors = @()
    if ($null -eq $Data) {
        $errors += "allow-list is null"
        return [PSCustomObject]@{ Ok = $false; Errors = $errors }
    }
    if ($Data.Services) {
        $i = 0
        foreach ($s in $Data.Services) {
            if ($null -eq $s) { $errors += "Services[$i] is null"; $i++; continue }
            if ($s -isnot [string]) { $errors += "Services[$i] is not a string (got $($s.GetType().Name))" }
            elseif ([string]::IsNullOrWhiteSpace($s)) { $errors += "Services[$i] is empty" }
            $i++
        }
    }
    if ($Data.Appx) {
        $i = 0
        foreach ($a in $Data.Appx) {
            if ($null -eq $a) { $errors += "Appx[$i] is null"; $i++; continue }
            if ($a -isnot [string]) { $errors += "Appx[$i] is not a string (got $($a.GetType().Name))" }
            elseif ([string]::IsNullOrWhiteSpace($a)) { $errors += "Appx[$i] is empty" }
            $i++
        }
    }
    if ($Data.Modules -and $Data.Modules.PSObject) {
        $idx = 0
        foreach ($p in $Data.Modules.PSObject.Properties) {
            $key = $p.Name
            $val = $p.Value
            if ([string]::IsNullOrWhiteSpace($key)) {
                $errors += "Modules[$idx] has empty key"; $idx++; continue
            }
            # A Modules key must be a known module name (kebab-case .ps1 filename)
            # so allow-listing an arbitrary string is caught early.
            if ($key -match '\s') {
                $errors += "Modules key '$key' contains whitespace (must be a valid module name)"
            }
            if ($null -eq $val) { $idx++; continue }
            if ($val -is [string]) {
                if ([string]::IsNullOrWhiteSpace($val)) { $errors += "Modules.$key value is empty string" }
            } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $j = 0
                foreach ($v in $val) {
                    if ($v -isnot [string]) { $errors += "Modules.$key[$j] is not a string (got $($v.GetType().Name))" }
                    elseif ([string]::IsNullOrWhiteSpace($v)) { $errors += "Modules.$key[$j] is empty" }
                    $j++
                }
            } else {
                $errors += "Modules.$key value is not a string or string array (got $($val.GetType().Name))"
            }
            $idx++
        }
    }
    if ($errors.Count -gt 0) {
        Write-Warn "allow-list schema errors in $Path`:"
        foreach ($e in $errors) { Write-Warn "  - $e" }
    }
    return [PSCustomObject]@{ Ok = ($errors.Count -eq 0); Errors = $errors }
}

function Read-ConfirmedString {
    param(
        [string]$Message,
        [int]$TimeoutSeconds = $Script:HighImpactTimeoutSeconds,
        [string[]]$ValidValues
    )
    # Non-interactive context: caller decides what to do; we return $null.
    if (-not (Test-IsInteractive)) { return $null }
    Write-Host "$Message" -NoNewline -ForegroundColor Yellow
    # Build a line of input from individual keypresses. Allows backspace, Enter
    # to submit, and gives the user a real timeout window to type the full
    # confirmation string. Echo is suppressed because Confirm-HighImpact is
    # meant for sensitive irreversible actions.
    $line = ''
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if ($Host.UI.RawUI.KeyAvailable) {
            $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            $c = $k.Character
            if ($c -eq "`r") {
                # Enter: submit whatever has been typed.
                Write-Host ""
                if ($line -in $ValidValues) { return $line }
                return $null
            } elseif ($c -eq "`b") {
                # Backspace: trim last char if any.
                if ($line.Length -gt 0) {
                    $line = $line.Substring(0, $line.Length - 1)
                }
            } elseif ($c -ge ' ') {
                $line += $c
            }
        } else {
            Start-Sleep -Milliseconds 50
        }
    }
    Write-Host ""
    return $null
}

function Confirm-HighImpact {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Impact,
        [switch]$DryRun
    )
    if ($DryRun) {
        Write-Info "DRY-RUN: would request confirmation for high-impact action: $Action"
        return $true
    }
    if (-not (Test-IsInteractive)) {
        Write-Warn "Non-interactive context (piped stdin, hidden window, or no console)."
        Write-Warn "High-impact action '$Action' was REJECTED. Re-run with -ConfirmImpact to bypass."
        return $false
    }
    Write-Host ""
    Write-Host "=== HIGH-IMPACT ACTION ===" -ForegroundColor Red
    Write-Host "Action : $Action" -ForegroundColor White
    Write-Host "Impact : $Impact" -ForegroundColor Yellow
    Write-Host ""
    # Accept the literal strings "Yes" and "yes" (case-sensitive) so the user
    # must deliberately type a full word — a single accidental keypress is
    # insufficient. Any other input (timeout, garbage, blank) is rejected.
    # -AssumeYes does NOT bypass this gate; use -ConfirmImpact for automation.
    $resp = Read-ConfirmedString -Message "Type Yes or yes to confirm: " -ValidValues @('Yes','yes')
    if ($null -ne $resp) { return $true }
    Write-Warn "High-impact action rejected (timed out or invalid input). Skipping."
    return $false
}

# ----------------------------------------------
# Dry-run guard
# ----------------------------------------------
function Invoke-Cmd {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Cmd,
        [bool]$DryRun,
        [string]$Description
    )
    if ($DryRun) {
        Write-Info "DRY-RUN: $Cmd"
        return
    }
    if ($Description) { Write-Info "Running: $Description" }
    $output = & $Cmd 2>&1
    # Some native commands (e.g. cmd /c ... 2>NUL) suppress the exit code and
    # return 0 even when the real command failed. We check LASTEXITCODE and throw
    # so callers' try/catch fires; if LASTEXITCODE is also 0 despite output being
    # present, it means the command intentionally swallowed it and we treat it as OK.
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        Write-Warn "Command exited $exit`: $Cmd"
        throw "Command failed (exit $exit): $Cmd"
    }
}
if ($MyInvocation.MyCommand.ModuleName) { Export-ModuleMember -Function @(
    'Invoke-SelfElevate','Test-IsAdmin','Test-WindowsVersion','Test-IsInteractive',
    'Write-Banner','Write-Section','Write-Pass','Write-Warn','Write-Info','Write-Skip',
    'Initialize-Logging','Add-Change','Close-Logging',
    'Show-MainMenu','Invoke-TimedPrompt',
    'New-Snapshot','Restore-Snapshot','New-SystemRestorePoint',
    'Get-AllowList','Set-AllowList','Test-AllowListSchema',
    'Read-ConfirmedString','Confirm-HighImpact',
    'Invoke-Cmd'
) }

