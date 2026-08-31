# Windows

[![Platform](https://img.shields.io/badge/platform-Windows-lightgray.svg)](https://github.com/)
[![Build Status](https://github.com/neohiro/windows/actions/workflows/release.yml/badge.svg)](https://github.com/neohiro/windows/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Windows 10 & 11 security hardening — automated and documented. This repository contains:

- **`Harden-Windows.ps1`** — the main modular hardening orchestrator (recommended entry point)
- **`bootstrap.ps1`** — one-line installer: `irm http://bit.ly/hardenwin | iex`
- **`harden.cmd`** — CLI launcher for the orchestrator
- **`modules/`** — individual hardening modules (ASR, firewall, services, debloat, etc.)
- **`lib/core.ps1`** — shared library: logging, snapshots, rollback, allow-lists

## ⚡ Quick start

```powershell
irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex -Profile Home
```

Or download and run locally:

```powershell
.\Harden-Windows.ps1 -Profile Home
.\Harden-Windows.ps1 -Profile Workstation
.\Harden-Windows.ps1 -DryRun           # preview without making changes
.\Harden-Windows.ps1 -Rollback         # restore last snapshot
.\Harden-Windows.ps1 -AssumeYes        # skip interactive prompts (CI/automation)
.\Harden-Windows.ps1 -ConfirmImpact    # bypass typing "Yes"/"yes" for high-impact actions
.\Harden-Windows.ps1 -ValidateAllowList # validate allow-list JSON and exit (no changes)
```

> **⚠️ Every interactive module shows a per-item impact warning before you choose.
> Some actions are irreversible without a reboot. Always review the impact column.**

## 🛑 Confirmation contract

High-impact actions (Print Spooler, biometrics service, tablet input, `.bat`/`.vbs`/`.js` re-association)
require you to **type the literal string `Yes` or `yes`** at the prompt and press Enter. Single-character
input (`y`, `Y`, `Enter`) is rejected — the full word is required so that headless terminals, accidental
keypresses, and default shells cannot accidentally confirm a destructive action.

| Flag | Effect on high-impact prompts |
|---|---|
| *(no flag)* | Type `Yes` or `yes` to proceed. |
| `-AssumeYes` | Skips non-destructive module prompts, but **does NOT bypass** high-impact gates. You must still type `Yes`/`yes`. |
| `-ConfirmImpact` | Bypasses high-impact gates entirely. Use only in CI/automation with a reviewed allow-list. |
| `-DryRun` | All high-impact gates are short-circuited (no real change is made regardless of input). |

To validate your allow-list JSON without applying anything: `.\Harden-Windows.ps1 -ValidateAllowList`.
Exits 0 on success, 1 on any schema error.

## 📋 Module impact reference

Every module below may change or remove operating system features. The **User Impact** column
describes what is lost or degraded. Review this before running with `-AssumeYes`.

### 🔴 High-impact modules — read carefully

| Module | What it does | User Impact if disabled / removed |
|---|---|---|
| **Print Spooler** (`usb_autoplay`) | Stops and disables the Print Spooler service | **No printing.** All USB, network, and PDF printers stop working. Re-enable with `Set-Service Spooler -StartupType Automatic; Start-Service Spooler`. PrintNightmare remote-code-execution risk is eliminated. |
| **File associations** (`fileassoc`) | Re-associates `.bat .vbs .js .jse .hta .wsf` to Notepad instead of the script host | **Scripts do not execute when double-clicked.** You must run them explicitly from PowerShell (`.\script.bat`) or Command Prompt. Power-user workflow break. |
| **AppX debloater** (`appx_debloater`) | Removes preinstalled Microsoft and third-party Store apps | Specific apps are removed — see the **AppX Impact Table** below. **Some removed apps cannot be restored without reinstalling from the Microsoft Store.** |
| **Service debloater** (`service_debloater`) | Disables or sets to Manual a curated list of 35 Windows services | See the **Service Impact Table** below. Some disables can break authentication (Biometrics), search, clipboard sync, or Xbox features. |

### 🟡 Medium-impact modules

| Module | What it does | User Impact |
|---|---|---|
| **Windows Defender + ASR** (`defender`) | Enables ASR rules, sandboxing, real-time protection, Exploit Protection | No user impact. Security posture is raised. ASR rules are advisory and may log events in the Windows Event Log. |
| **Firewall** (`firewall`) | Enables Windows Firewall with block rules for common attack vectors | No direct user impact. Legitimate inbound connections (RDP, file sharing, development servers) may be blocked if not explicitly allowed. |
| **SMB / Network** (`smb_network`) | Disables SMBv1, enables signing, disables NetBIOS/LLMNR | No impact on modern networks. Legacy devices or very old NAS units may become inaccessible. |
| **PowerShell logging** (`powershell_logging`) | Enables script block logging, module logging, transcription | No direct user impact. Administrators can see all PowerShell activity in Event Viewer. |
| **Audit logging** (`audit_logging`) | Enables comprehensive Windows audit policies | No direct user impact. Additional events written to the Security Event Log. |
| **Privacy** (`privacy`) | Disables telemetry and data-sharing services | Some personalization features in Microsoft apps may degrade. Error reporting to Microsoft stops. |
| **Account lockout** (`account_lockout`) | Sets account lockout threshold, resets policy | No direct user impact. Legitimate failed logins (e.g. mistyped password) now lock the account after 5 attempts. |
| **PowerShell v2** (`powershell_v2`) | Disables Windows PowerShell 2.0 engine | Fileless attacks via PowerShell v2 are blocked. No impact on modern PowerShell 5.1/7 workflows. |
| **USB AutoPlay** (`usb_autoplay`) | Disables AutoPlay on all drive types | USB media no longer auto-opens when inserted. Manual navigation required. |
| **Browser hardening** (`browser`) | Configures Chrome/Edge group policy for security | No direct user impact. Some browser extensions or enterprise policies may behave differently. |
| **Office hardening** (`office`) | Disables macros, DDE in Office apps | **Macros in Office documents are blocked.** Legitimate macro workflows in Excel/Word require signed or explicitly allowed macros. |
| **Biometrics** (`biometrics`) | Enables facial recognition anti-spoofing, disables camera on lock screen | No direct impact. Enhanced protection against biometric spoofing on lock screen. |
| **Backup/Recovery** (`backup_recovery`) | Configures Windows Backup and File History | No direct impact. Backup schedules are enabled if not already set. |
| **Optional Features** (`optional_features`) | Disables unwanted Windows optional features | Specific Windows features (e.g. Hyper-V,Containers) are disabled. Only affects features already present. |
| **Core settings** (`core`) | Enables DEP, UAC, secure DLL load order | No direct user impact. Hardens the OS baseline. |

---

## 🖥️ Service debloater impact table

> **⚠️ Printing**: PrintSpooler is the most impactful entry. Disabling it means **no printing from any application until the service is re-enabled**. Use `KeepPrintSpooler` in your allow-list if you have a printer.

| Service | Default action | User Impact |
|---|---|---|
| `PrintSpooler` | **Disabled** | **NO PRINTING.** All printers stop. Required by most print workflows. |
| `TabletInputService` | Disabled | **On-screen keyboard and handwriting panel unavailable.** Accessibility risk for touch-only devices. Keep if you rely on the OSK. |
| `WbioSrvc` (Biometrics) | Manual | **Windows Hello fingerprint/face login unavailable.** Users must use PIN or password. |
| `WSearch` (Search Indexer) | Manual | **Start menu and File Explorer search is slower.** Index-based results disabled. |
| `SysMain` (Superfetch) | Manual | **Apps may launch more slowly after a fresh reboot.** Memory prefetch reduced. |
| `DiagTrack` (Telemetry) | Disabled | **CEIP telemetry not sent.** Some personalization features in Microsoft apps degrade. |
| `OneSyncSvc` | Disabled | **Mail, Calendar, People, and UWP apps stop syncing your Microsoft account data.** |
| `CDPUserSvc` | Disabled | **Clipboard sync between PC and phone, Cast to Device, Projecting fail.** |
| `sshd` | Disabled | **Cannot SSH into this machine.** Only affects users running an SSH server. |
| `RemoteRegistry` | Disabled | **Security gain:** other computers cannot read this machine's registry remotely. |
| `SharedAccess` (ICS) | Disabled | **Cannot share internet via hotspot/tethering.** |
| `RemoteAccess` (VPN) | Disabled | **VPN and DirectAccess connectivity disabled.** |
| `WMPNetworkSvc` | Disabled | **DLNA/UPnP media streaming from WMP to TVs/speakers disabled.** |
| `WerSvc` | Disabled | **Error reports not sent to Microsoft.** Problem Reports tool shows no data. |
| `lfsvc` (Geolocation) | Disabled | **Maps apps cannot determine device location.** Weather apps may degrade. |
| `TrkWks` (Link Tracking) | Disabled | **Shortcuts and linked files on network shares may break after renames.** |
| `MapsBroker` | Disabled | **Offline maps cannot be downloaded or updated.** |
| `edgeupdate` / `edgeupdatem` | Manual | **Microsoft Edge cannot auto-update.** Manual updates required. |
| `XblAuthManager` / `XblGameSave` / `XboxGipSvc` / `XboxNetApiSvc` | Disabled | **Xbox social, cloud save, multiplayer, and wireless controller features impaired.** |
| `BcastDVRUserService` | Disabled | **Xbox Game Bar recording and broadcasting unavailable.** |
| `CaptureService` / `FrameServer` | Disabled | **Some screenshot/scraping APIs and multi-app camera access degrade.** |
| `HomeGroupListener` / `HomeGroupProvider` | Disabled | **HomeGroup file sharing unavailable** (deprecated since Win10 1803 — unlikely to affect any real user). |
| `NetTcpPortSharing` | Disabled | **WCF services using net.tcp binding cannot start.** Rare. |
| `RetailDemo` | Disabled | Retail demo mode unavailable (store PCs only). |
| `Fax` | Disabled | Windows Fax and Scan cannot send/receive faxes. |
| `UnistoreSvc` / `PimIndexMaintenanceSvc` | Disabled | UWP apps cannot save structured user data / contact search. |
| `dmwappushservice` | Disabled | Some third-party apps may not receive push notifications. |

---

## 📦 AppX debloater impact table

> **⚠️ Removed apps cannot always be restored from the Store.** Some preinstalled apps are tied to system components. Test on a non-production machine first, or use the `[A]` allow-list shortcut during the prompt.

| App pattern | User Impact |
|---|---|
| `Microsoft.BingWeather` | No built-in Weather app or tile |
| `Microsoft.GetHelp` | No "Get Help" app |
| `Microsoft.Getstarted` | No Tips welcome app |
| `Microsoft.Messaging` | No built-in SMS/Messaging app |
| `Microsoft.People` | No People contacts app |
| `Microsoft.WindowsAlarms` | No Alarms & Clock app |
| `Microsoft.WindowsCamera` | No built-in Camera app |
| `microsoft.windowscommunicationsapps` | **No Mail and Calendar** (combined package). Use Outlook Web or the Store version separately. |
| `Microsoft.WindowsFeedbackHub` | No Feedback Hub; some diagnostic data paths affected |
| `Microsoft.WindowsMaps` | No Maps app |
| `Microsoft.WindowsSoundRecorder` | No Voice Recorder app |
| `Microsoft.YourPhone` | No Phone Link / PC-phone integration |
| `Microsoft.549981C3F5F10` (Cortana) | Cortana consumer removed |
| `Microsoft.Microsoft3DViewer` | No 3D Viewer app |
| `Microsoft.ScreenSketch` | No Snip & Sketch / Snipping Tool |
| `Microsoft.PowerAutomateDesktop` | **Cannot record UI automations with Power Automate Desktop.** |
| `Microsoft.OneNote` | No preinstalled OneNote (reinstall from Office/Store if needed) |
| `Microsoft.Office.Sway` | No Sway presentation app |
| `SpotifyAB.SpotifyMusic*` | Preinstalled Spotify removed (reinstall from Store if needed) |
| `king.com.*` | Preinstalled Candy Crush games removed |
| `Duolingo*` / `PandoraMedia*` / `AdobeSystemIncorporated*` | Preinstalled third-party apps removed |
| `Microsoft.Advertising.Xaml*` | Some apps depending on the Ad SDK may not function |

---

## 🔒 ASR rule reference

Attack Surface Reduction rules are enabled in **Audit mode** (logged but not enforced) or **Enabled mode** (blocked).
This script enables them in **Enabled mode**. No direct user impact — legitimate activity is rarely affected.

| ASR Rule | What it blocks |
|---|---|
| `BlockOfficeChildProcess` | Office macros spawning child processes |
| `BlockProcessInjection` | Code injection into other processes |
| `BlockWin32ApiCallsInMacros` | Win32 API calls from Office VBA macros |
| `BlockOfficeExecutableContent` | Executable content in Office documents |
| `BlockObfuscatedScripts` | Obfuscated PowerShell / JScript / VBScript |
| `BlockExecutableEmailContent` | Executable attachments caught at the email client |
| `BlockJsVbScriptLaunchExe` | Script files launching executables |
| `BlockLsassCredTheft` | Reading LSASS for credential dumping (Mimikatz) |
| `BlockUntrustedUsb` | Unsigned executables on USB drives |
| `BlockAdobeReaderChild` | Adobe Reader spawning child processes |
| `BlockWmiPersistence` | WMI event subscription persistence |
| `BlockPsExecWmi` | Lateral movement via PsExec/WMI remote process launch |

---

## 🛡️ Allow-lists

All interactive modules respect the allow-list at `%PROGRAMDATA%\HardenWindows\Config\allowlist.json`.
You can also pass values at runtime:

```powershell
.\Harden-Windows.ps1 -AllowListOverride @{ Services = @('PrintSpooler','WbioSrvc') }
```

Or add items interactively with the `[A]` shortcut during the appx/service prompts.

---

## ↩️ Rollback

Every non-dry-run execution creates a named snapshot before applying changes.
Rollback restores the registry hives and services from that snapshot.

```powershell
.\Harden-Windows.ps1 -Rollback
# Or from the interactive menu: press R
```

Rollback does **not** remove apps installed by the AppX debloater — only system services and registry settings.
System Restore points are separate and created on demand.

---

## 📖 Manual steps (supplementary)

Windows button + R for Advanced System Settings:
```
sysdm.cpl
```
Click Performance > Data Execution Prevention and select All Apps.

Click Remote > Turn off remote access.

- Uninstall Remote Desktop Manager & OneDrive in Apps
- Enable encryption if available in Windows settings
- Enable virtualization if available & other protection settings
- Disable access to microphone, camera and other sensors if not by default
- Disable anything but IPv4 & IPv6 in network adapter settings
- Set a secure DNS (dnscrypt, dnslow.me or WARP or 9.9.9.9,...)
- Install [Exploit Protection](https://github.com/neohiro/ExploitProtection) for most common software
- Install your favorite internet browser (or later for user account only)
- Install possible VPN software (or later for user account only)
- Install [OnionFruit](https://github.com/dragonfruitnetwork/onionfruit) for Tor (or later for user account only)
- Harden Defender via [ConfigureDefender](https://github.com/AndyFul/ConfigureDefender)
- Harden windows extremely (STIG) with [this git](https://gist.github.com/neohiro/da3dc76dcf77c67878f02fd71ac17358)
- Debloat Windows further

Windows + R to open Services:
```
services.msc
```
Turn off services in relation to **remote desktop connection** + others you don't use.

Windows + R to open Windows Features
```
optionalfeatures
```
Turn off all remote services and dependencies you will not use

Windows + R for Device Manager:
```
devmgmt.msc
```
Look for useless devices and disable them.

- Install [Ultimate Windows Tweaker](https://www.thewindowsclub.com/downloads/UWT5.zip) and
  	- if not via ConfigDefender before, set a restore point	 
	- disable ADMINISTRATIVE SHARES $
 	- disable unnecessary accesses to Windows (regedit,..)
	- turn off user tracking
   	- turn off telemetry
	- harden network adapter

- Install [Spybot 2](https://www.safer-networking.org/products/spybot-free-edition/download-mirror-1/) and immunize the system
- Get a non administrator user account to continue your Windows journey


Further on, make use of all the Windows tools available:

Software and Updates:

- Regularly install all Windows updates to get the latest security patches.
- Keep all other software and drivers up to date.
- Uninstall any unnecessary applications to reduce the attack surface.

Account and Authentication:

- Use a standard user account for daily tasks and reserve the administrator account for system changes.
- Enable multifactor authentication or use Windows Hello (PIN, fingerprint, or face).
- Use strong, unique passwords for all accounts, and consider a password manager.
- Configure account lockout policies to prevent brute-force attacks.

Windows Security Features:

- Ensure that Windows Defender Antivirus is enabled and up-to-date.
- Turn on the Windows Firewall and configure it to block unnecessary network traffic.
- Enable User Account Control (UAC) to get prompts for administrative tasks.
- Use BitLocker to encrypt your drives, which protects your data if the device is lost or stolen.
- Enable Secure Boot in your UEFI settings to ensure only trusted software loads during startup.
- Use Controlled Folder Access to protect your important files from ransomware.

Privacy and System Configuration:

- Review and adjust your privacy settings to control what data is collected.
- Disable unnecessary services and features to reduce potential vulnerabilities.
- Configure browser security settings, such as enabling SmartScreen and using strict tracking prevention (see [htmlinfo](https://github.com/neohiro/htmlinfo)).
- Use Windows Sandbox or Microsoft Defender Application Guard for opening untrusted files or Browse suspicious websites in an isolated environment.

## 🔒 Core isolation & memory integrity

Windows button + R to check the TPM (required by BitLocker, Windows Hello and Credential Guard):
```
tpm.msc
```
The TPM should read *ready*. Then open Windows Security → **Device security → Core isolation** and switch ON:
- **Memory integrity (HVCI)** — stops malicious drivers from writing kernel memory.
- **Microsoft vulnerable driver blocklist**.
- On newer hardware also enable **Firmware protection / Secure Launch** where offered.

If memory integrity reports an incompatible driver, update or remove that driver — don't switch the protection off.

## 👤 Credential & account protection

- Enable **LSA Protection** so malware can't dump credentials from memory (elevated Command Prompt):
```
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v RunAsPPL /t REG_DWORD /d 2 /f
```
- Windows 10/11 **Enterprise/Education**: additionally enable **Credential Guard** (isolates secrets in virtualization-based security) — follow "Manage Windows Credential Guard" on Microsoft Learn.
- Deploy **Windows LAPS** so the local Administrator password is unique per device and auto-rotated — one shared local admin password is a single point of failure across all your machines.
- Open Local Security Policy (`secpol.msc`) and set:
  - Account Policies → Password Policy: minimum **14 characters**, history 24, complexity enabled.
  - Account Policies → Account Lockout Policy: lock after **5** bad attempts, 15-minute reset.
  - Local Policies → Security Options: **rename** the built-in Administrator and Guest accounts, enable *Interactive logon: Don't display last user name*, and add a logon message title/text.
- Raise UAC to the top slider (Control Panel → User Accounts → *Change User Account Control settings* → always notify).
- Let idle sessions lock themselves: enable **Dynamic Lock** (Settings → Accounts → Sign-in options) plus a screensaver lock timeout.

## 🌐 Network protocol hardening

Legacy LAN protocols are the easiest foothold on a home network — kill them (elevated PowerShell):
```powershell
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force
```
- Stop **name-poisoning attacks** (Responder/Inveigh): with the same regedit path pattern disable LLMNR:
```
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" /v EnableMulticast /t REG_DWORD /d 0 /f
```
  then for every NIC: adapter Properties → IPv4 → Advanced → WINS tab → **Disable NetBIOS over TCP/IP**, and untick *Automatically detect settings* in Internet Options → Connections → LAN settings (WPAD).
  
## ⚡ PowerShell & scripting

```powershell
Set-ExecutionPolicy RemoteSigned -Force
```
- Enable **script block logging**, **module logging** and **transcription** (gpedit.msc → Administrative Templates → Windows Components → Windows PowerShell). Fileless attacks still leave traces worth reading.
- If you never run legacy `.vbs` / `.js` / `.wsf` scripts, re-associate them to Notepad exactly like the automated script does for `.bat`.

## 🖨️ USB, AutoPlay & printing

- Group Policy (gpedit.msc): *Turn off Autoplay for all drives*, and for shared/kiosk machines consider *Removable Disks: Deny read access*.
- No printer attached? Disable the print spooler entirely (PrintNightmare class of bugs lives here):
```powershell
Stop-Service Spooler -PassThru | Set-Service -StartupType Disabled
```

## 💾 Backups & recovery plan

Hardening without backups is a gamble — ransomware and dead SSDs happen to everyone eventually:

- Follow **3-2-1**: three copies of important data, on two different media, one copy off-site **and offline** (ransomware happily encrypts everything on mapped drives).
- Turn on **File History** or scheduled system images; verify System Protection is enabled for C:.
- Export your **BitLocker recovery key** to your Microsoft account AND store a printed copy somewhere safe — then confirm you can actually retrieve it.
- Create a **USB recovery drive** (`recoverydrive`) right after setup, while the system is healthy.

## ✅ Post-setup verification

- Run one **Microsoft Defender Offline scan** (Windows Security → Virus & threat protection → Scan options) once setup settles.
- Audit your work from elevated PowerShell:
```powershell
Get-MpComputerStatus            # real-time protection, tamper protection, signatures
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, RequireSecuritySignature
Get-ChildItem HKLM:\SYSTEM\CurrentControlSet\Control\Lsa | Select-Object RunAsPPL
```
- Check Windows Update → Advanced options → enable *Receive updates for other Microsoft products*, then update until nothing is pending.

---


<p align="center">
  <a href="https://github.com/sponsors/neohiro"><img src="https://img.shields.io/badge/Sponsor%20on%20GitHub-%E2%9D%A4-EA4AAA?logo=githubsponsors&style=for-the-badge" alt="GitHub Sponsors"></a>&nbsp;&nbsp;
  <a href="https://www.patreon.com/frenzypenguin_media"><img src="https://img.shields.io/badge/Patreon-frenzypenguin__media-F96854?logo=patreon&style=for-the-badge" alt="Support on Patreon"></a>
</p>
#   C I   t r i g g e r 
 
 


---

## 🔗 Related & Sponsorship

- 💖 [Sponsor neohiro on GitHub](https://github.com/sponsors/neohiro) — covers API + hosting costs
- 🌐 [neohiro.github.io](https://neohiro.github.io/) — main site
- 🎬 [FrenzyPenguin Media](https://frenzypenguin-media.github.io/) — video deep-dives
- 🧬 [transhumanists](https://transhumanists.github.io/) — companion dashboard for human progress
