# Harden-Windows

[![CI](https://github.com/neohiro/windows/actions/workflows/ci.yml/badge.svg)](https://github.com/neohiro/windows/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/neohiro/windows?include_prereleases&label=latest)](https://github.com/neohiro/windows/releases/latest)
[![Scoop](https://img.shields.io/badge/scoop-harder--windows-7C4DFF?logo=scoop)](https://scoop.sh)
[![winget](https://img.shields.io/badge/winget-neohiro.HardenWindows-0078D4?logo=windows)](https://github.com/microsoft/winget-pkgs)
[![License](https://img.shields.io/github/license/neohiro/windows)](LICENSE)
[![Discussions](https://img.shields.io/github/discussions/neohiro/windows?color=7C4DFF)](https://github.com/neohiro/windows/discussions)

**One-command Windows 10/11 hardening.** Downloads → double-click → done.

`neohiro/windows` re-imagined as a fully automated, interactive hardening suite with allow-lists, rollback, and debloaters built in.

---

## Quick start

### One line, two-phase UX

**Phase 1 — bootstrap (run this as Administrator, once):**

```powershell
irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex
```

What happens: the bootstrap self-elevates, downloads all 25 files to `%LOCALAPPDATA%\HardenWindows\repo`, verifies every file against its SHA-256 hash (from `manifest.sha256`), then launches the interactive menu. On next run, it reuses the cache — pass `-Update` to force a fresh download.

> **Requires Administrator.** The bootstrap will attempt to self-elevate; if you run it from a non-elevated prompt it will silently request elevation and restart itself. If you pipe `irm | iex` into a non-Administrator session, Windows will prompt for UAC — accept it.

**Phase 2 — interactive menu** lets you pick a profile, review per-item options, and apply. Each ambiguous choice waits 15 seconds with the **safe default pre-selected**; press a key to override.

**To skip hash verification** (e.g. in air-gapped environments where the manifest can't be fetched):

```powershell
irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex -SkipVerify
```

**To preview without touching the system:**

```powershell
irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex -DryRun
```

**To restore after a bad run:**

```powershell
irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex -Profile Home -Rollback
```

---

### From a local clone

```powershell
# Elevated PowerShell
.\Harden-Windows.ps1 -Profile Home

# Preview without applying
.\Harden-Windows.ps1 -Profile Home -DryRun

# Restore previous state
.\Harden-Windows.ps1 -Rollback
```

Or double-click `harden.cmd` from an elevated Command Prompt.

---

## Profiles

| Profile | What it does |
|---------|-------------|
| `Home` | Privacy + Defender + ASR + Firewall + Lockout + Debloat. Safe for family PCs. |
| `Workstation` | Above + service debloater + strict ASR + AppX removal. |
| `Developer` | Above but keeps PowerShell remoting, WinRM, WSL, dev tooling. |
| `Custom` | Interactive module picker. |

---

## One-command UX

Every ambiguous choice is pre-debated and answered by default — the script auto-selects the **safe, hardened option** and waits 15 seconds for you to override.

| Prompt | Default | Override |
|--------|---------|---------|
| Restore point before changes? | `Y` | `N` |
| Disable Print Spooler? | `N` | `Y` |
| Lock script files to Notepad (.bat/.vbs)? | `N` | `Y` |
| Service debloater per-item? | **interactive** | `S`=skip rest |
| Appx debloater per-item? | `Y` (remove) | `N`=keep, `A`=add to allow-list |
| Reboot after? | `N` | `Y` |

---

## Allow-list workflow

Anything in `allowlist.json` is **exempt** from hardening:

```json
{
  "Services": ["wuauserv", "WinRM"],
  "Appx":     ["Microsoft.WindowsCalculator*"],
  "Modules": {
    "firewall":  ["BlockCalcExe"],
    "smb_network": ["DisableSMB1"]
  }
}
```

Edit before running — or use `A` mid-session to add items interactively. The file lives in:
```
%ProgramData%\HardenWindows\Config\allowlist.json
```
Also editable in `config/default.AllowList.psd1` for source control.

---

## Module reference

| Module | What it hardens |
|--------|----------------|
| `core` | LSA RunAsPPL, Credential Guard VBS, UAC top, TPM/Secure Boot check |
| `defender` | ASR rules (12 rules), Exploit Protection, PUA, cloud, Network Protection |
| `firewall` | All profiles on, LOLBin outbound blocks (8 binaries) |
| `smb_network` | SMB1/NetBIOS/LLMNR/ICMP redirect/WinRM/RPC/RestrictAnonymous |
| `account_lockout` | 14-char min pass, 24 history, 5-attempt lockout, 15-min reset |
| `usb_autoplay` | Autoplay off, optional Print Spooler kill |
| `powershell_logging` | ScriptBlock + Module logging, RemoteSigned policy |
| `audit_logging` | 4688 cmdline, auditpol (9 subcategories), 1 GB log sizes |
| `browser` | Edge SmartScreen, Chrome 13-policy GPO |
| `office` | Macros → block, ProtectedView, DDE disabled (Office 12–16) |
| `privacy` | Telemetry → 0, Ad ID off, location deny, GameDVR off, Consumer features off |
| `fileassoc` | .bat/.vbs/.js/.hta → Notepad (ransomware friction) |
| `biometrics` | Anti-spoof, lock screen camera, voice above lock off |
| `powershell_v2` | Remove PSv2 engine |
| `service_debloater` | **Interactive**: 30+ services, per-item Disable/Manual/Auto, allow-list |
| `appx_debloater` | **Interactive**: provisioned + user Appx, wildcard match, allow-list |
| `optional_features` | SMB1/PSv2/WorkFolders/XPS/IE optional features |
| `backup_recovery` | Recovery drive reminder, BitLocker key protector check |

---

## Rollback

```powershell
.\harden.cmd Rollback
```
Restores service states and registry values from the last pre-hardening snapshot.

Snapshots live in `%ProgramData%\HardenWindows\State\`.

---

## Logs & artifacts

| File | Location |
|------|----------|
| Transcript | `%ProgramData%\HardenWindows\Logs\harden-YYYYMMDD-HHMMSS.log` |
| Change log (JSON) | `%ProgramData%\HardenWindows\Logs\changes-YYYYMMDD-HHMMSS.json` |
| Allow-list | `%ProgramData%\HardenWindows\Config\allowlist.json` |
| Snapshots | `%ProgramData%\HardenWindows\State\snapshot-*\manifest.json` (+ sibling .reg + services.json) |

---

## Architecture

```
neohiro/windows/
├── harden.cmd              ← one-command launcher (self-elevates)
├── Harden-Windows.ps1      ← master orchestrator
├── modules/                ← one file per hardening domain
│   ├── core.ps1
│   ├── defender.ps1
│   ├── firewall.ps1
│   ├── smb_network.ps1
│   ├── account_lockout.ps1
│   ├── usb_autoplay.ps1
│   ├── powershell_logging.ps1
│   ├── audit_logging.ps1
│   ├── browser.ps1
│   ├── office.ps1
│   ├── privacy.ps1
│   ├── fileassoc.ps1
│   ├── biometrics.ps1
│   ├── powershell_v2.ps1
│   ├── service_debloater.ps1    ← interactive per-service allow-list
│   ├── appx_debloater.ps1        ← interactive per-app allow-list
│   ├── optional_features.ps1
│   └── backup_recovery.ps1
├── lib/
│   └── core.ps1            ← UI, logging, rollback, allow-list engine
├── config/
│   ├── profiles.psd1       ← Home / Workstation / Developer presets
│   └── default.AllowList.psd1  ← source-controlled allow-list
├── manifest.sha256         ← SHA-256 hashes; bootstrap verifies every file
    └── tests/
        └── regression.ps1      ← 50 end-to-end tests (parse, load, dry-run, snapshot, allow-list, bootstrap, security invariants)
```

---

## Command-line flags

```powershell
.\Harden-Windows.ps1                           # interactive
.\Harden-Windows.ps1 -Profile Home             # preset
.\Harden-Windows.ps1 -Profile Workstation -DryRun  # preview
.\Harden-Windows.ps1 -Rollback                 # restore last session
.\Harden-Windows.ps1 -SkipDebloat              # skip service/appx debloaters
.\Harden-Windows.ps1 -AllowListOverride @{ Services=@('wuauserv') }
```

---

## Testing

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\regression.ps1
```

The suite covers: parse cleanliness for every `.ps1`/`.psd1`, lib/module/function loadability, all 18 module `Set-*` functions, allow-list get/set roundtrip + corrupt-file handling, allow-list cross-reference against real modules, profile uniqueness (no dupes, no module in both `Modules` and `Skip`), snapshot directory uniqueness, `Restore-Snapshot` against missing/empty manifest, dry-run isolation (no system writes), and end-to-end orchestrator dry-run with zero errors.

Exit code 0 on success, non-zero on any failure. Add to CI before merging changes.

---

## Credits

Original `windows_hardening.cmd` and manual steps by [neohiro](https://github.com/neohiro/windows).
Enhanced with allow-list engine, interactive debloaters, rollback, and module architecture.

ASR rules from [@jaredhaight](https://github.com/jaredhaight) (firewall),
[@ricardojba](https://github.com/ricardojba) (DLL Safe Order Search),
[@jessicaknotts](https://github.com/jessicaknotts) (Exploit Guard testing).

---

> **Security hardening is not a one-time event.** Re-run after major Windows updates.
> Review `%ProgramData%\HardenWindows\Logs\` after each run.
