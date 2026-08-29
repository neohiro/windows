# Windows
[![Platform](https://img.shields.io/badge/platform-Windows-lightgray.svg)](https://github.com/)
[![Build Status](https://github.com/neohiro/windows/actions/workflows/release.yml/badge.svg)](https://github.com/neohiro/windows/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Windows 10 & 11 New Install Manual Settings

Using run dialog and via basic settings you can start improving security inside settings after a fresh Windows installation:

## ⚡ Automated hardening script

[`windows_hardening.cmd`](windows_hardening.cmd) automates a large part of this guide: hardened file associations against ransomware, Defender & ASR configuration, firewall rules, DLL load-order protection, privacy settings and more.

1. Download `windows_hardening.cmd` from this repository.
2. Open an **elevated** Command Prompt (`Run as administrator`).
3. Run the script and review its output.
4. Reboot afterwards.

> ⚠️ **Note:** the script re-associates `.bat` and other script files to open in Notepad instead of executing. If you legitimately use these extensions you will need to run them manually from cmd/PowerShell or right-click → *Run as administrator*.

Credits & references are documented at the top and bottom of the script — thanks [@jaredhaight](https://github.com/jaredhaight) (firewall config), [@ricardojba](https://github.com/ricardojba) (DLL Safe Order Search) and [@jessicaknotts](https://github.com/jessicaknotts) (Exploit Guard testing). For debloating, see [Windows10Debloater](https://github.com/Sycnex/Windows10Debloater).

## 🖱️ Manual steps

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
#   C I   t r i g g e r  
 