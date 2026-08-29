# Harden-Windows - Library
# Core utilities: Prerequisite checks, UI helpers, logging, rollback, allow-list

$Script:LogDir    = "$env:ProgramData\HardenWindows\Logs"
$Script:StateDir  = "$env:ProgramData\HardenWindows\State"
$Script:ConfigDir = "$env:ProgramData\HardenWindows\Config"

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
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
        exit
    }
}

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WindowsVersion {
    $os = Get-CimInstance Win32_OperatingSystem
    if ($os.Caption -match 'Windows 1[01]' -or $os.BuildNumber -ge 10240) { return $true }
    return $false
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
    $Script:Changes = @()

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
    if ($null -eq $Script:Changes) { $Script:Changes = @() }
    $Script:Changes += [PSCustomObject]@{
        Timestamp = (Get-Date).ToString("o")
        Module    = $Module
        Setting   = $Setting
        OldValue  = $OldValue
        NewValue  = $NewValue
        Status    = $Status
    }
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
        [int]$TimeoutSeconds = 15,
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
        $suffix  = -join ((Get-Random -Count 4 -InputObject ([char[]]'0123456789abcdef')))
        $snapDir = "$Script:StateDir\snapshot-$Label-$stamp-$suffix"
        $attempt++
        try {
            $null = New-Item -ItemType Directory -Path $snapDir -ErrorAction Stop
            break  # success
        } catch {
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
        # reg.exe exports the subtree. A non-zero exit just means the key is absent (fine on Home).
        # We only add the .reg file to the manifest if reg.exe produced a non-empty result.
        reg export $h $file /y 2>$null | Out-Null
        if ((Test-Path $file) -and ((Get-Item $file).Length -gt 0)) {
            $regIndex += @{ Key = $h; File = $file }
        } else {
            # Empty or zero-byte file (key absent). Remove the stub to keep the
            # snapshot directory clean.
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

    # Manifest: must be written last so Restore-Snapshot can rely on it as the
    # integrity gate (if the manifest is absent or corrupt, restore bails early).
    $manifest = @{
        Timestamp = (Get-Date).ToString("o")
        Label     = $Label
        RegFiles  = $regIndex
        Services  = $svcPath
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
        foreach ($svc in Get-Service) { $current[$svc.Name] = $svc }
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
    if (Test-Path $path) {
        try {
            $content = Get-Content $path -Raw
            if ([string]::IsNullOrWhiteSpace($content)) { return $default }
            $parsed = $content | ConvertFrom-Json
            if ($null -eq $parsed) { return $default }
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
    [System.IO.File]::WriteAllText($path, ($Data | ConvertTo-Json -Depth 10), [System.Text.Encoding]::UTF8)
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
    # LastExitCode may be stale or 0 if the command chain never set it (e.g.
    # native command never invoked). Check it and throw so callers' try/catch
    # runs. Some commands (e.g. cmd /c ... 2>NUL) suppress the actual code;
    # in that case we treat a non-error output as success.
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
    'Get-AllowList','Set-AllowList',
    'Invoke-Cmd'
) }

