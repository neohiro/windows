# Windows
Windows 10 & 11 New Install Manual Settings

Using run dialog and via basic settings you can start improving security inside settings after a fresh Windows installation:

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
	- Configure browser security settings, such as enabling SmartScreen and using strict tracking prevention (see []).
	- Use Windows Sandbox or Microsoft Defender Application Guard for opening untrusted files or Browse suspicious websites in an isolated environment.
