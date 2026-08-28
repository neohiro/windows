# Contributing to Harden-Windows

Thank you for contributing! This project values **correctness over speed**, **simplicity over features**, and **user safety above all**.

## Quick Start

```powershell
# 1. Fork & clone
git clone https://github.com/YOUR-FORK/windows.git
cd windows

# 2. Run tests (must pass before any PR)
powershell -ExecutionPolicy Bypass -File tests/regression.ps1

# 3. Make changes, test again
# 4. Open PR with clear description
```

## Development Rules

### 1. All Tests Must Pass
```powershell
powershell -ExecutionPolicy Bypass -File tests/regression.ps1
# 71 tests, 0 failures required
```

### 2. No `Invoke-Expression` / `iex`
Static analysis fails the build. Use:
- `& $scriptPath` for script invocation
- `& $functionName` for function calls
- `Invoke-Command` / `Invoke-Expression` only in bootstrap for `irm | iex` pattern

### 3. Module Convention
Each module in `modules/`:
```powershell
# File: modules/my_feature.ps1
function Set-MyFeature {
    param(
        [bool]$DryRun,
        [object]$AllowList
    )
    # Implementation here
}
Export-ModuleMember -Function Set-MyFeature
```
- Function name: `Set-<ModuleName>` (PascalCase)
- Accepts `-DryRun` and `-AllowList` parameters
- Returns nothing; uses `Add-Change` for logging

### 4. Update `fnMap` in `Harden-Windows.ps1`
```powershell
$fnMap = @{
    # ... existing ...
    'my_feature' = 'Set-MyFeature'
}
```

### 5. Add to Profile (`config/profiles.psd1`)
```powershell
@{
    Home = @{
        Modules = @('core', 'defender', ..., 'my_feature')
        Skip    = @()
    }
    # ...
}
```

### 6. Update Manifest
```powershell
# After changes, regenerate manifest.sha256
Get-FileHash -Algorithm SHA256 (Get-ChildItem -Recurse -File | Where-Object { $_.Extension -in '.ps1','.psd1','.cmd','.md' }) | ForEach-Object { "$($_.Hash.ToLower())  $($_.FullName.Replace($PSScriptRoot+'\',''))" } | Set-Content manifest.sha256
```

## Code Style

- **PowerShell 5.1 compatible** (no `??`, `?[]`, `forEach` method)
- **PascalCase** for functions, `camelCase` for parameters
- **Comment-based help** for public functions (`.SYNOPSIS`, `.PARAMETER`)
- **Explicit parameter types** (`[string]`, `[bool]`, `[object]`)
- **`$ErrorActionPreference = 'Stop'`** in scripts (continue in interactive)

## Testing Guidelines

- New modules: add `Set-<Module>` test to `tests/regression.ps1`
- Dry-run must produce zero side effects (verified by regression test)
- Allow-list integration: test with `Get-AllowList` / `Set-AllowList` roundtrip
- Snapshot/rollback: verify `New-Snapshot` + `Restore-Snapshot` cycle

## Pull Request Checklist

- [ ] `tests/regression.ps1` passes (71/71)
- [ ] `manifest.sha256` updated with new hashes
- [ ] `fnMap` updated in `Harden-Windows.ps1`
- [ ] Profile(s) updated in `config/profiles.psd1`
- [ ] No `Invoke-Expression` introduced
- [ ] Dry-run tested manually on Windows 10/11
- [ ] CHANGELOG entry added (or "No user-facing changes")

## Issue Labels

| Label | Meaning |
|-------|---------|
| `bug` | Regression or incorrect behavior |
| `enhancement` | New hardening module or feature |
| `security` | Vulnerability or hardening gap |
| `docs` | README, comments, help text |
| `test` | Regression test improvements |
| `windows-10` / `windows-11` | OS-specific behavior |

## Code of Conduct

- Be respectful. No harassment, trolling, or political arguments.
- Technical disagreements: discuss trade-offs, not people.
- Security issues: follow [SECURITY.md](SECURITY.md) — no public disclosure until coordinated.

## Questions?

Open a [Discussion](https://github.com/neohiro/windows/discussions) or [Issue](https://github.com/neohiro/windows/issues).