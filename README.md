# windows
Windows New Start - Manual Settings

Using run dialog and via basic settings you can start improving after a fresh Windows installation:
Windows button + R - Advanced System Settings:
```
sysdm.cpl
```
Click Performance > Data Execution Prevention and select All Apps. 
Click Remote > Turn off remote access

- Uninstall Remote Desktop Manager & OneDrive in Apps
- Enable encryption if not default in Windows settings
- Enable virtualization & other protection settings
- Disable access to microphone, camera and other sensors by default
- Disable anything but IPv4 & IPv6 in network adapter settings
- Set a secure DNS (dnscrypt, 9.9.9.9,...)
- Install Exploit Protection for most common software
- Harden windows via ConfigureDefender
- Harden windows with this git
- Debloat Windows further

Windows button + R - Open Services:
```
services.msc
```
Turn off services in relation to **remote desktop connection** + others you don't use.

Windows button + R - Device Manager:
```
devmgmt.msc
```
Look for useless devices and disable them.

- Install Ultimate Windows Tweaker and 
	- disable ADMINISTRATIVE SHARES $
	- turn off user tracking
	- harden network adapter
	- disable unnecessary access to Windows

- Install Spybot 2 and immunize the system
- Get a non administrator user account to continue your Windows journey
