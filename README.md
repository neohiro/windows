# Windows
Windows 10 & 11 New Start for Manual Settings

Using run dialog and via basic settings you can start improving after a fresh Windows installation:

Windows button + R for Advanced System Settings:
```
sysdm.cpl
```
Click Performance > Data Execution Prevention and select All Apps.

Click Remote > Turn off remote access.

- Uninstall Remote Desktop Manager & OneDrive in Apps
- Enable encryption if not default in Windows settings
- Enable virtualization & other protection settings
- Disable access to microphone, camera and other sensors by default
- Disable anything but IPv4 & IPv6 in network adapter settings
- Set a secure DNS (dnscrypt, dnslow.me or WARP or 9.9.9.9,...)
- Install [Exploit Protection](https://github.com/neohiro/ExploitProtection) for most common software
- Install your favorite internet browser (or later for user account only)
- Install possible VPN software (or later for user account only)
- Install [OnionFruit](https://github.com/dragonfruitnetwork/onionfruit) for Tor
- Harden Defender via [ConfigureDefender](https://github.com/AndyFul/ConfigureDefender)
- Harden windows extremely with [this git](https://gist.github.com/neohiro/da3dc76dcf77c67878f02fd71ac17358)
- Debloat Windows further

Windows + R to open Services:
```
services.msc
```
Turn off services in relation to **remote desktop connection** + others you don't use.

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
