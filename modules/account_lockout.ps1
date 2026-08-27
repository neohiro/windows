# account_lockout.ps1 -- Local Security Policy, lockout policy, password policy
$Module = 'account_lockout'

function Set-AccountLockoutSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Account lockout & password policy"

    if ($AllowList -contains 'AccountPolicies') {
        Write-Skip "Account policies allow-listed."
        return
    }

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # Use secedit for the proper local security policy export/import.
    # Use unique temp names (process ID + random) so concurrent or back-to-back
    # runs don't collide on a fixed %TEMP%\secedit.inf which can fail with
    # "The process cannot access the file because it is being used by another process."
    $tmpInf = Join-Path $env:TEMP "secedit-$PID-$(Get-Random).inf"
    $tmpDb  = Join-Path $env:TEMP "secedit-$PID-$(Get-Random).sdb"

    if ($DryRun) {
        Write-Info "DRY-RUN: would set 14-char min length, 5-attempt lockout, 15-min reset"
        Add-Change $Module 'secpol:MinPasswordLen' '0' '14' 'DRY'
        Add-Change $Module 'secpol:LockoutBadCount' '0' '5' 'DRY'
        Add-Change $Module 'secpol:ResetLockoutCount' '0' '15' 'DRY'
        Add-Change $Module 'secpol:LockoutDuration' '0' '15' 'DRY'
        Add-Change $Module 'secpol:PasswordHistory' '0' '24' 'DRY'
        return
    }

    try {
        secedit /export /cfg $tmpInf /quiet | Out-Null
        $inf = Get-Content $tmpInf -Raw

        $replacements = @{
            'MinimumPasswordLength\s*=\s*\d+'     = 'MinimumPasswordLength = 14'
            'PasswordHistorySize\s*=\s*\d+'        = 'PasswordHistorySize = 24'
            'PasswordComplexity\s*=\s*\d+'         = 'PasswordComplexity = 1'
            'MaximumPasswordAge\s*=\s*\d+'         = 'MaximumPasswordAge = 365'
            'LockoutBadCount\s*=\s*\d+'            = 'LockoutBadCount = 5'
            'LockoutDuration\s*=\s*\d+'            = 'LockoutDuration = 15'
            'ResetLockoutCount\s*=\s*\d+'          = 'ResetLockoutCount = 15'
        }
        foreach ($p in $replacements.GetEnumerator()) {
            $inf = [regex]::Replace($inf, $p.Key, $p.Value)
        }
        # secedit requires a Unicode (UTF-16 LE with BOM) INI. Set-Content with
        # -Encoding Unicode sometimes drops the BOM on some PS hosts, which
        # causes secedit /configure to fail with "Invalid data". Use the .NET
        # API directly to guarantee the byte order mark.
        [System.IO.File]::WriteAllText($tmpInf, $inf, [System.Text.Encoding]::Unicode)

        secedit /configure /db $tmpDb /cfg $tmpInf /quiet | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "secedit /configure exited with $LASTEXITCODE; policy may be unchanged"
            Add-Change $Module 'secpol:all' 'defaults' 'secedit-failed' 'ERR'
        } else {
            Write-Pass "Local security policy: min length=14, history=24, lockout=5/15min"
            Add-Change $Module 'secpol:all' 'defaults' 'hardened' 'OK'
        }
    } catch {
        Write-Warn "secedit failed: $_"
        Add-Change $Module 'secpol:all' 'defaults' 'exception' 'ERR'
    }

    # Cleanup temp secedit artifacts so they don't accumulate in %TEMP%
    Remove-Item -Force -ErrorAction SilentlyContinue $tmpInf, $tmpDb
}

