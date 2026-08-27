# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-08-27

### Added
- First public release of the `neohiro/windows` hardening suite.
- One-line bootstrap: `irm https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.ps1 | iex`.
- Interactive main menu (Home / Workstation / Developer / Custom / Dry-run / Rollback).
- 18 hardening modules covering Defender, firewall, SMB/network, account lockout,
  PowerShell logging, audit policy, USB/autoplay, browser, Office, privacy,
  biometrics, file associations, PowerShell v2, service debloater, Appx
  debloater, optional features, and backup/recovery reminders.
- Allow-list engine with default per-profile `.psd1`, runtime JSON overrides,
  and a CLI override (`-AllowListOverride`).
- Snapshot/rollback via `reg export/import` and `sc qc / config`.
- SHA-256 manifest verification on every bootstrap download.
- `-DryRun`, `-SkipDebloat`, `-Rollback`, `-SkipVerify`, `-Update` switches.
- 53-test regression suite (parse, load, dry-run, snapshot, allow-list,
  bootstrap, security invariants).

### Security
- All registry write commands are `reg add ... /f`; non-zero exit codes throw
  and are recorded as `ERR` in the change log.
- Service hardening uses `Set-Service -StartupType` with the type-safe enum.
- `Invoke-Expression` is never used; every shell command goes through
  `Invoke-Cmd` which throws on non-zero exit.
- UAC elevation is forwarded with serializable scalar arguments only
  (`-Profile`, `-DryRun`, `-SkipDebloat`, `-Rollback`); no hashtables.

### Notes
- Replaces the deprecated `wmic.exe` call in `smb_network.ps1` with a pure
  registry-based NetBIOS-over-TCP disable.
- Compatible with PowerShell 5.1 (Windows 10 / 11 default). The `??`
  null-coalescing operator is polyfilled.
