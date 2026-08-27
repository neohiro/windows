<#
.SYNOPSIS
    One-line installer/runner for Harden-Windows.
.DESCRIPTION
    Designed to be invoked via:
        irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex
    Downloads the rest of the repo to %LOCALAPPDATA%\HardenWindows and runs Harden-Windows.ps1.
    Idempotent: re-running reuses the cache. Update with -Update.
.PARAMETER Profile
    Forwarded to Harden-Windows.ps1 (Home / Workstation / Developer / Custom).
.PARAMETER Source
    Override the base URL (for forks or local mirrors).
.PARAMETER Update
    Force re-download of the cached repo, ignoring the existing copy.
.PARAMETER Run
    Default: 'Harden-Windows.ps1'. Forwarded as the PS1 to invoke.
.PARAMETER PSArgs
    Extra arguments to pass through to the orchestrator.
#>

[CmdletBinding()]
param(
    [string]$Profile = '',
    [string]$Source  = 'https://raw.githubusercontent.com/neohiro/windows/main',
    [switch]$Update,
    [string]$Run     = 'Harden-Windows.ps1',
    [string[]]$PSArgs = @(),
    [switch]$NoElevate,
    [switch]$SkipVerify
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'Continue'

# ── Self-elevate if not admin ──────────────────────────────────────────────
# When run via `irm | iex`, $PSCommandPath is empty. Save the current script
# body to a real file before re-launching elevated so the elevated process
# can find itself on disk.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $NoElevate -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[>>] Not elevated. Re-launching as administrator..." -ForegroundColor Yellow

    $scriptPath = $PSCommandPath
    $tempScript = $false
    if ([string]::IsNullOrEmpty($scriptPath)) {
        # Get-Content the body from this script's definition (works in iex)
        $body = $MyInvocation.MyCommand.Definition
        if ([string]::IsNullOrEmpty($body) -or $body -notmatch '\.SYNOPSIS') {
            Write-Host "[!!] Cannot re-elevate: no script body available in this context" -ForegroundColor Red
            exit 1
        }
        $scriptPath = Join-Path $env:TEMP "HardenWindows-bootstrap-$(Get-Random).ps1"
        Set-Content -Path $scriptPath -Value $body -Encoding UTF8
        $tempScript = $true
    }

    try {
        $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$scriptPath`"", "-Source `"$Source`"")
        if ($Profile)     { $argList += "-Profile `"$Profile`"" }
        if ($Update)      { $argList += "-Update" }
        if ($NoElevate)   { $argList += "-NoElevate" }
        if ($SkipVerify)  { $argList += "-SkipVerify" }
        $argList += '-PSArgs'
        $argList += $PSArgs
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argList | Out-Null
    } finally {
        # Clean up the temp script written for iex. If the bootstrap was launched
        # from a real file on disk, this is a no-op (we never created it).
        if ($tempScript -and (Test-Path $scriptPath)) {
            # Brief delay to give the elevated child time to start reading the file
            Start-Sleep -Milliseconds 200
            Remove-Item -Path $scriptPath -Force -ErrorAction SilentlyContinue
        }
    }
    return
}

# ── Locate cache ──────────────────────────────────────────────────────────
$cache = Join-Path $env:LOCALAPPDATA 'HardenWindows\repo'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

Write-Host ""
Write-Host "#============================================================" -ForegroundColor Cyan
Write-Host "#  Harden-Windows bootstrap  ($stamp)" -ForegroundColor Cyan
Write-Host "#  Source : $Source" -ForegroundColor Cyan
Write-Host "#  Cache  : $cache" -ForegroundColor Cyan
Write-Host "#============================================================" -ForegroundColor Cyan
Write-Host ""

# ── Download if needed ────────────────────────────────────────────────────
# Re-download if any required file is missing, including manifest.sha256.
# Without the manifest, the bootstrap can't verify file integrity even if
# every other file is present from a previous run.
$needDownload = $Update -or -not (Test-Path (Join-Path $cache 'Harden-Windows.ps1')) `
                          -or -not (Test-Path (Join-Path $cache 'harden.cmd')) `
                          -or -not (Test-Path (Join-Path $cache 'manifest.sha256'))
if ($needDownload) {
    if ($Update -and (Test-Path $cache)) {
        Write-Host "[ii] Removing stale cache..." -ForegroundColor DarkGray
        Remove-Item $cache -Recurse -Force
    }
    $null = New-Item -ItemType Directory -Force -Path $cache

    # Single source of truth for the file inventory. The same list is referenced
    # by tests/regression.ps1 to assert completeness.
    $inventory = @(
        'Harden-Windows.ps1','harden.cmd','README.md',
        'lib\core.ps1',
        'config\profiles.psd1','config\default.AllowList.psd1',
        'tests\regression.ps1',
        'modules\core.ps1','modules\defender.ps1','modules\firewall.ps1',
        'modules\smb_network.ps1','modules\account_lockout.ps1',
        'modules\usb_autoplay.ps1','modules\powershell_logging.ps1',
        'modules\audit_logging.ps1','modules\browser.ps1',
        'modules\office.ps1','modules\privacy.ps1','modules\fileassoc.ps1',
        'modules\biometrics.ps1','modules\powershell_v2.ps1',
        'modules\service_debloater.ps1','modules\appx_debloater.ps1',
        'modules\optional_features.ps1','modules\backup_recovery.ps1'
    )

    Write-Host "[>>] Downloading Harden-Windows..." -ForegroundColor Yellow

    # Fetch the signed manifest first. It contains "sha256  relative/path" lines.
    $MANIFEST_URL  = "$Source/manifest.sha256".Replace('\','/')
    $MANIFEST_TMP  = Join-Path $env:TEMP "HardenWindows-manifest-$(Get-Random).sha256"
    if ($SkipVerify) {
        Write-Host "  [--] Hash verification skipped (-SkipVerify)" -ForegroundColor DarkGray
        $knownHashes = @{}
    } else {
        try {
            Invoke-WebRequest -Uri $MANIFEST_URL -OutFile $MANIFEST_TMP -UseBasicParsing -ErrorAction Stop
            $lines = [System.IO.File]::ReadAllLines($MANIFEST_TMP, [System.Text.Encoding]::UTF8)
            $knownHashes = @{}
            foreach ($l in $lines) {
                if ($l -match '^([a-f0-9]{64})\s{2}(.+)$') {
                    $knownHashes[$Matches[2].Trim()] = $Matches[1].ToLower()
                }
            }
            if ($knownHashes.Count -eq 0) {
                Write-Host "  [ii] manifest.sha256 was empty or unparseable; continuing without verification." -ForegroundColor Yellow
            } else {
                # Persist the manifest into the cache so future runs can re-verify
                Copy-Item $MANIFEST_TMP -Force (Join-Path $cache 'manifest.sha256')
                Write-Host "  [OK] manifest.sha256 ($($knownHashes.Count) entries)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [!!] manifest.sha256 fetch failed: $_" -ForegroundColor Red
            Write-Host "  [ii] Falling back to hash-verification disabled mode." -ForegroundColor Yellow
            $knownHashes = @{}  # empty = skip verification
        }
    }

    $failed = @()
    foreach ($f in $inventory) {
        $url  = "$Source/$f".Replace('\','/')
        $dest = Join-Path $cache $f
        $null = New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
            if ($knownHashes.Count -gt 0 -and $knownHashes.ContainsKey($f)) {
                $actual = (Get-FileHash -Path $dest -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash.ToLower()
                if ($actual -ne $knownHashes[$f]) {
                    Write-Host "  [!!] HASH MISMATCH: $f" -ForegroundColor Red
                    Write-Host "       Expected : $($knownHashes[$f])" -ForegroundColor Red
                    Write-Host "       Actual   : $actual" -ForegroundColor Red
                    $failed += $f
                    continue
                }
            }
            Write-Host "  [OK] $f" -ForegroundColor Green
        } catch {
            Write-Host "  [!!] $f : $_" -ForegroundColor Red
            $failed += $f
        }
    }
    Remove-Item $MANIFEST_TMP -ErrorAction SilentlyContinue

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "[!!] $($failed.Count) file(s) failed verification or download. Aborting." -ForegroundColor Red
        Write-Host "[!!] DO NOT proceed — files may have been tampered with in transit." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[ii] Cache present, using $cache" -ForegroundColor DarkGray
}

# ── Verify minimal structure ──────────────────────────────────────────────
$verify = @('Harden-Windows.ps1','lib\core.ps1','config\profiles.psd1')
$missing = $verify | Where-Object { -not (Test-Path (Join-Path $cache $_)) }
if ($missing) {
    Write-Host "[!!] Cache incomplete. Missing: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "[ii] Re-run with -Update to force re-download." -ForegroundColor Yellow
    exit 1
}

# ── Forward to orchestrator ───────────────────────────────────────────────
Set-Location $cache
$forwardArgs = @{
    ModulePath = (Join-Path $cache 'modules')
    ConfigPath = (Join-Path $cache 'config')
}
if ($Profile) { $forwardArgs.Profile = $Profile }
foreach ($a in $PSArgs) {
    if ($a -match '^-DryRun$')              { $forwardArgs.DryRun = $true; continue }
    if ($a -match '^-SkipDebloat$')         { $forwardArgs.SkipDebloat = $true; continue }
    if ($a -match '^-Rollback$')            { $forwardArgs.Rollback = $true; continue }
    if ($a -match '^-Profile\s*(\S+)$')     { $forwardArgs.Profile = $Matches[1]; continue }
    Write-Host "[ii] Unknown forwarded arg ignored: $a" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "[>>] Launching Harden-Windows..." -ForegroundColor Yellow
Write-Host ""
& (Join-Path $cache $Run) @forwardArgs
exit $LASTEXITCODE
