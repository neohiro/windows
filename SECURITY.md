# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Do not open a public issue** for security vulnerabilities.

Instead, email **security@neohiro.dev** (or open a [private security advisory](https://github.com/neohiro/windows/security/advisories/new)) with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We aim to:
- Acknowledge within 48 hours
- Provide initial assessment within 7 days
- Release a fix within 30 days (coordinated disclosure)

## Security Model

### Bootstrap Integrity
- All files verified via `manifest.sha256` (26-file SHA-256 manifest)
- Bootstrap downloads manifest first, then verifies each file
- HTML/404 detection prevents error-page injection
- `-SkipVerify` flag explicitly opts out (not default)

### Execution Safety
- Dry-run mode (`-DryRun`) previews all changes without writing
- Interactive prompts default to safe options (15s timeout)
- Rollback restores registry + service state from snapshot
- No `Invoke-Expression` in any module (static analysis verified)

### Allow-List Defense
- User-controlled exemptions via `%ProgramData%\HardenWindows\Config\allowlist.json`
- Source-controlled defaults in `config/default.AllowList.psd1`
- CLI override: `-AllowListOverride @{ Services=@('wuauserv') }`

### Privilege Handling
- Self-elevation via UAC (standard Windows mechanism)
- No persistent elevated services or scheduled tasks
- Runs once, writes logs to `%ProgramData%\HardenWindows\Logs\`

## Supply Chain

- GitHub Actions CI runs regression suite on every push
- CodeQL security analysis weekly + on release
- Release artifacts signed via GitHub Attestations (SLSA L1)
- Dependabot enabled for GitHub Actions dependencies

## Threat Model

| Threat | Mitigation |
|--------|------------|
| Malicious bootstrap download | SHA-256 manifest verification, HTTPS only |
| Compromised release asset | GitHub Attestations, tag protection rules |
| Malicious module code | Static analysis (no IEX), regression tests |
| Unintended system changes | Dry-run default, safe prompts, rollback |
| Persistence/backdoor | No background services, one-shot execution |

## Hardening Scope

This tool **applies** security settings. It does **not**:
- Install kernel drivers
- Modify boot configuration (except BitLocker key protector check)
- Disable Windows Update (wuauserv is allow-listed by default)
- Replace system binaries
- Require persistent background components