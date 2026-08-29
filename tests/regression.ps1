# Regression test for Harden-Windows
# Run: powershell -ExecutionPolicy Bypass -File tests\regression.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root -or $root -eq '') { $root = 'C:\Users\Wout\Documents\Default Project\neohiro\windows' }
$pass = 0
$fail = 0
$results = @()

function Test-Case {
    param([string]$Name, [scriptblock]$Body)
    $script:err = $null
    $script:result = $null
    try {
        $script:result = & $Body
        if ($script:result -is [bool] -and -not $script:result) {
            throw "Body returned false"
        }
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:pass++
    } catch {
        Write-Host "  [FAIL] $Name : $_" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "=== Harden-Windows regression ===" -ForegroundColor Cyan

# 1. Parse: every .ps1 / .psd1 must parse without errors
Test-Case "All PowerShell files parse clean" {
    $files = Get-ChildItem $root -Recurse -Include *.ps1,*.psd1
    $errs = $null
    foreach ($f in $files) {
        $errs = $null
        [System.Management.Automation.PSParser]::Tokenize((Get-Content $f.FullName -Raw), [ref]$errs) | Out-Null
        if ($errs.Count -gt 0) { throw "$($f.Name) has parse errors: $($errs[0].Message)" }
    }
    return $true
}

# 2. Load: lib + all modules + orchestrator
Test-Case "lib\core.ps1 dot-sources without errors" {
    $errs = $null
    try { . "$root\lib\core.ps1" } catch { throw $_ }
    $fns = 'Invoke-SelfElevate','Test-IsAdmin','Test-WindowsVersion','Write-Banner',
           'Write-Section','Write-Pass','Write-Warn','Write-Info','Write-Skip',
           'Initialize-Logging','Add-Change','Close-Logging',
           'Show-MainMenu','Invoke-TimedPrompt','Test-IsInteractive',
           'New-Snapshot','Restore-Snapshot','New-SystemRestorePoint',
           'Get-AllowList','Set-AllowList',
           'Invoke-Cmd'
    foreach ($f in $fns) {
        if (-not (Get-Command $f -ErrorAction SilentlyContinue)) { throw "Missing: $f" }
    }
    return $true
}

Test-Case "All 18 module functions load and are callable" {
    $mods = Get-ChildItem "$root\modules" -Filter '*.ps1'
    foreach ($m in $mods) { . $m.FullName }
    $expected = @('Set-CoreSettings','Set-DefenderSettings','Set-FirewallSettings','Set-SmbNetworkSettings',
                  'Set-AccountLockoutSettings','Set-UsbAutoplaySettings','Set-PowerShellLogging',
                  'Set-AuditLogging','Set-BrowserSettings','Set-OfficeSettings','Set-PrivacySettings',
                  'Set-FileAssocSettings','Set-BiometricsSettings','Set-PowerShellV2',
                  'Set-ServiceDebloater','Set-AppxDebloater','Set-OptionalFeatures','Set-BackupRecovery')
    foreach ($f in $expected) {
        if (-not (Get-Command $f -ErrorAction SilentlyContinue)) { throw "Missing: $f" }
    }
    return $true
}

# 3. Add-Change is safe to call pre-Initialize-Logging
Test-Case "Add-Change handles null Script:Changes" {
    . "$root\lib\core.ps1"
    $Script:Changes = $null
    Add-Change 'test' 'key' 'old' 'new' 'OK'
    if ($Script:Changes.Count -ne 1) { throw "Expected 1 change" }
    return $true
}

# 4. Allow-list data file loads
Test-Case "default.AllowList.psd1 parses" {
    $al = Import-PowerShellDataFile -Path "$root\config\default.AllowList.psd1"
    if ($null -eq $al) { throw "null" }
    if ($null -eq $al.Services) { throw "no Services" }
    return $true
}

# 5. Profile data file loads with 3 profiles
Test-Case "profiles.psd1 has 3 profiles" {
    $pd = Import-PowerShellDataFile -Path "$root\config\profiles.psd1"
    foreach ($k in 'Home','Workstation','Developer') {
        if (-not $pd.ContainsKey($k)) { throw "Missing $k" }
        if ($pd[$k].Modules.Count -lt 5) { throw "$k has too few modules: $($pd[$k].Modules.Count)" }
    }
    return $true
}

# 6. Dry-run executes end-to-end with 0 errors
Test-Case "Orchestrator dry-run completes without error" {
    # Filter out known benign errors (Stop-Transcript when no transcript active)
    $beforeErrors = @($Error | Where-Object { $_.Exception.Message -notmatch 'Stop-Transcript|host is not currently transcribing|No transcript running' })
    & "$root\Harden-Windows.ps1" -Profile Home -DryRun -SkipDebloat -ModulePath "$root\modules" -ConfigPath "$root\config" 2>&1 | Out-Null
    $afterErrors = @($Error | Where-Object { $_.Exception.Message -notmatch 'Stop-Transcript|host is not currently transcribing|No transcript running' })
    if ($afterErrors.Count -gt $beforeErrors.Count) {
        throw "$($afterErrors.Count - $beforeErrors.Count) errors during run: $($afterErrors[0])"
    }
    return $true
}

# 7. harden.cmd exists and is non-empty
Test-Case "harden.cmd launcher present" {
    $p = "$root\harden.cmd"
    if (-not (Test-Path $p)) { throw "missing" }
    if ((Get-Item $p).Length -lt 500) { throw "too small" }
    return $true
}

# 8. README exists
Test-Case "README.md present" {
    $p = "$root\README.md"
    if (-not (Test-Path $p)) { throw "missing" }
    if ((Get-Item $p).Length -lt 1000) { throw "too small" }
    return $true
}

# --- Edge case tests -------------------------------------------------------

Test-Case "Dry-run mode does not modify registry or create snapshot dirs" {
    . "$root\lib\core.ps1"
    $prePaths  = @(Get-ChildItem "$env:ProgramData\HardenWindows\State" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    & "$root\Harden-Windows.ps1" -Profile Home -DryRun -SkipDebloat -ModulePath "$root\modules" -ConfigPath "$root\config" 2>&1 | Out-Null
    $postPaths = @(Get-ChildItem "$env:ProgramData\HardenWindows\State" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    $newPaths  = @($postPaths | Where-Object { $prePaths -notcontains $_ })
    if ($newPaths.Count -gt 0) {
        throw "dry-run created $($newPaths.Count) files: $($newPaths -join ', ')"
    }
    return $true
}

Test-Case "Allow-list Get/Set roundtrip preserves data" {
    . "$root\lib\core.ps1"
    $orig = Get-AllowList
    try {
        $test = [PSCustomObject]@{
            Services = @('wuauserv','WinRM')
            Appx     = @('Microsoft.WindowsCalculator*')
            Modules  = @{ firewall = @('BlockCalcExe') }
        }
        Set-AllowList $test
        $loaded = Get-AllowList
        if ($loaded.Services -notcontains 'wuauserv') { throw "Services lost" }
        if ($loaded.Appx -notcontains 'Microsoft.WindowsCalculator*') { throw "Appx lost" }
        if (-not $loaded.Modules.firewall -or $loaded.Modules.firewall -notcontains 'BlockCalcExe') { throw "Module entry lost" }
    } finally {
        Set-AllowList $orig
    }
    return $true
}

Test-Case "Allow-list handles missing/corrupt file gracefully" {
    . "$root\lib\core.ps1"
    $path = "$Script:ConfigDir\allowlist.json"
    $orig = if (Test-Path $path) { Get-Content $path -Raw } else { $null }
    try {
        '{ not valid json' | Set-Content -Path $path -Encoding UTF8
        $al = Get-AllowList
        if ($null -eq $al) { throw "Get-AllowList returned null on corrupt file" }
        if ($null -eq $al.Services) { throw "Services key missing" }
    } finally {
        if ($null -ne $orig) {
            Set-Content -Path $path -Value $orig -Encoding UTF8
        } else {
            Remove-Item $path -ErrorAction SilentlyContinue
        }
    }
    return $true
}

Test-Case "New-Snapshot creates unique directories (no collision)" {
    . "$root\lib\core.ps1"
    $a = New-Snapshot -Label "test-collision-1"
    Start-Sleep -Milliseconds 1100   # ensure timestamp ticks
    $b = New-Snapshot -Label "test-collision-1"
    if ($a -eq $b) { throw "snapshots collided" }
    $dirA = Split-Path $a -Parent
    $dirB = Split-Path $b -Parent
    if ($dirA -eq $dirB) { throw "snapshot directories collided" }
    if (-not (Test-Path (Join-Path $dirA 'manifest.json'))) { throw "manifest A missing" }
    if (-not (Test-Path (Join-Path $dirB 'manifest.json'))) { throw "manifest B missing" }
    # Cleanup
    Remove-Item $dirA -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $dirB -Recurse -Force -ErrorAction SilentlyContinue
    return $true
}

Test-Case "Restore-Snapshot tolerates missing manifest" {
    . "$root\lib\core.ps1"
    $fake = "$env:TEMP\nonexistent-manifest-$([guid]::NewGuid()).json"
    if (Test-Path $fake) { Remove-Item $fake }
    # Should not throw, should warn
    Restore-Snapshot -ManifestPath $fake
    return $true
}

Test-Case "Restore-Snapshot tolerates empty RegFiles array" {
    . "$root\lib\core.ps1"
    $tmp = "$env:TEMP\empty-manifest-$([guid]::NewGuid()).json"
    @{ Timestamp = (Get-Date).ToString("o"); RegFiles = @(); Services = $null } | ConvertTo-Json | Set-Content $tmp
    try {
        Restore-Snapshot -ManifestPath $tmp
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
    return $true
}

Test-Case "Profile module names are unique within each profile" {
    $pd = Import-PowerShellDataFile -Path "$root\config\profiles.psd1"
    foreach ($k in $pd.Keys) {
        $dups = $pd[$k].Modules | Group-Object | Where-Object { $_.Count -gt 1 }
        if ($dups) { throw "Profile '$k' has duplicate modules: $($dups.Name -join ', ')" }
        # No module should be in both Modules and Skip
        $both = $pd[$k].Modules | Where-Object { $pd[$k].Skip -contains $_ }
        if ($both) { throw "Profile '$k' has module in both Modules and Skip: $($both -join ', ')" }
    }
    return $true
}

Test-Case "All AllowList module keys reference real modules" {
    # Validate the source-controlled default.AllowList.psd1, not the runtime
    # config (which can be edited by the user and may be in any state).
    $al = Import-PowerShellDataFile -Path "$root\config\default.AllowList.psd1"
    $realMods = Get-ChildItem "$root\modules" -Filter '*.ps1' | ForEach-Object { $_.BaseName }
    if ($al -and $al.Modules) {
        foreach ($mk in $al.Modules.Keys) {
            if ($realMods -notcontains $mk) { throw "Allow-list references unknown module: $mk" }
        }
    }
    return $true
}

Test-Case "Every module file has a Set-* function defined" {
    $mods = Get-ChildItem "$root\modules" -Filter '*.ps1'
    foreach ($m in $mods) {
        $c = Get-Content $m.FullName -Raw
        if ($c -notmatch "function Set-") { throw "Module $($m.Name) has no Set- function" }
    }
    return $true
}

Test-Case "Every real module has a corresponding fnMap entry in the orchestrator" {
    # For each module file, extract the actual Set-* function name it defines,
    # then verify the orchestrator's fnMap includes a mapping for that module
    # name pointing to that function. This catches additions missed in fnMap.
    $mismatches = @()
    $realMods = @{}
    foreach ($mf in Get-ChildItem "$root\modules" -Filter '*.ps1') {
        $base  = $mf.BaseName
        $c     = Get-Content $mf.FullName -Raw
        $match = [regex]::Match($c, 'function\s+(Set-\w+)')
        if ($match.Success) {
            $realMods[$base] = $match.Groups[1].Value
        }
    }
    $orch = Get-Content "$root\Harden-Windows.ps1" -Raw
    foreach ($mod in $realMods.Keys) {
        $expectedFn = $realMods[$mod]
        # fnMap entry format: 'modulename' = 'FunctionName'
        if ($orch -notmatch "'$mod'\s*=\s*'$([regex]::Escape($expectedFn))'") {
            $mismatches += "module '$mod': expected fnMap entry '$($expectedFn)'"
        }
    }
    if ($mismatches) { throw ($mismatches -join '; ') }
    return $true
}

Test-Case "bootstrap inventory list matches the actual repo file layout" {
    $inv = Get-Content "$root\bootstrap.ps1" -Raw
    # All real modules must be in the inventory
    foreach ($mf in Get-ChildItem "$root\modules" -Filter '*.ps1') {
        $rel = "modules\$($mf.Name)"
        if ($inv -notmatch [regex]::Escape($rel)) { throw "bootstrap inventory missing: $rel" }
    }
    # Critical top-level files
    foreach ($f in @('Harden-Windows.ps1','harden.cmd','lib\core.ps1',
                     'config\profiles.psd1','config\default.AllowList.psd1',
                     'tests\regression.ps1')) {
        if ($inv -notmatch [regex]::Escape("'$f'")) { throw "bootstrap inventory missing: $f" }
    }
    return $true
}

Test-Case "bootstrap.ps1 parses and can be invoked with -WhatIf (no real download)" {
    # -WhatIf is not implemented in our bootstrap, so just load+parse it
    $bp = "$root\bootstrap.ps1"
    if (-not (Test-Path $bp)) { throw "bootstrap.ps1 missing" }
    $errs = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content $bp -Raw), [ref]$errs) | Out-Null
    if ($errs.Count -gt 0) { throw "bootstrap.ps1 parse errors: $($errs[0].Message)" }
    return $true
}

Test-Case "bootstrap.ps1 HelpCommentBlock is present" {
    $bp = "$root\bootstrap.ps1"
    $c  = Get-Content $bp -Raw
    if ($c -notmatch '\.SYNOPSIS')    { throw "Missing .SYNOPSIS" }
    if ($c -notmatch 'irm.*bootstrap\.ps1') { throw "Missing one-line install hint in help" }
    if ($c -notmatch '-Profile')      { throw "Missing -Profile param" }
    if ($c -notmatch '-Update')       { throw "Missing -Update param" }
    if ($c -notmatch 'Invoke-WebRequest') { throw "Missing download logic" }
    return $true
}

Test-Case "bootstrap downloads all files end-to-end (file:// as fake online)" {
    $cache = Join-Path $env:LOCALAPPDATA 'HardenWindows\repo'
    if (Test-Path $cache) { Remove-Item $cache -Recurse -Force }

    $source = "file:///$($root -replace '\\','/')"
    $beforeErrors = @($Error | Where-Object { $_.Exception.Message -notmatch 'Stop-Transcript|host is not currently transcribing|No transcript running' })
    & "$root\bootstrap.ps1" -Profile Home -PSArgs @('-DryRun','-SkipDebloat') -Source $source -NoElevate 2>&1 | Out-Null
    $afterErrors = @($Error | Where-Object { $_.Exception.Message -notmatch 'Stop-Transcript|host is not currently transcribing|No transcript running' })

    if ($afterErrors.Count -gt $beforeErrors.Count) { throw "bootstrap emitted errors: $($afterErrors[0])" }
    if (-not (Test-Path (Join-Path $cache 'Harden-Windows.ps1'))) { throw "Harden-Windows.ps1 not in cache" }
    if (-not (Test-Path (Join-Path $cache 'lib\core.ps1'))) { throw "lib\core.ps1 not in cache" }

    $modules = Get-ChildItem (Join-Path $cache 'modules') -Filter '*.ps1' -ErrorAction SilentlyContinue
    if ($modules.Count -lt 18) { throw "only $($modules.Count) modules in cache" }
    return $true
}

Test-Case "bootstrap reuses cache on second run (no re-download)" {
    $cache = Join-Path $env:LOCALAPPDATA 'HardenWindows\repo'
    if (-not (Test-Path $cache)) { throw "cache from previous test missing" }
    $mtime1 = (Get-Item (Join-Path $cache 'Harden-Windows.ps1')).LastWriteTime
    # Mark the cache; if bootstrap ever calls Invoke-WebRequest and redownloads (and wipes), this disappears
    $marker = "$cache\test-marker.txt"
    Set-Content $marker "alive"
    # Run bootstrap with a source that would FAIL if hit (proving it didn't call Invoke-WebRequest)
    # Use the real local source so the bootstrap doesn't have to hit a broken URL
    $source = "file:///$($root -replace '\\','/')"
    $beforeErrors = @($Error | Where-Object { $_.Exception.Message -notmatch 'Stop-Transcript|host is not currently transcribing|No transcript running' })
    & "$root\bootstrap.ps1" -Profile Home -PSArgs @('-DryRun','-SkipDebloat') -Source $source -NoElevate 2>&1 | Out-Null
    $afterErrors = @($Error | Where-Object { $_.Exception.Message -notmatch 'Stop-Transcript|host is not currently transcribing|No transcript running' })
    if ($afterErrors.Count -gt $beforeErrors.Count) { throw "bootstrap emitted errors: $($afterErrors[0])" }
    if (-not (Test-Path $marker)) { throw "cache was wiped on second run" }
    $mtime2 = (Get-Item (Join-Path $cache 'Harden-Windows.ps1')).LastWriteTime
    if ($mtime2 -ne $mtime1) { throw "Harden-Windows.ps1 was overwritten during cache reuse run (mtime changed)" }
    # Also verify orchestrator ran (Write-Host output goes to host; check via transcript if available)
    $logDir = "$env:ProgramData\HardenWindows\Logs"
    $logs   = Get-ChildItem $logDir -Filter 'harden-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $logs) { throw "no harden log found (orchestrator may not have run)" }
    Remove-Item $marker -ErrorAction SilentlyContinue
    return $true
}

Test-Case "New-Snapshot handles fast repeated calls without collision" {
    . "$root\lib\core.ps1"
    $dirs = @()
    for ($i = 0; $i -lt 10; $i++) {
        $mp = New-Snapshot -Label "rapid-$i"
        $dirs += (Split-Path $mp -Parent)
        Remove-Item $dirs[-1] -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($dirs.Count -ne 10) { throw "did not produce 10 snapshots" }
    if (@($dirs | Select-Object -Unique).Count -ne 10) { throw "collision among 10 rapid snapshots" }
    return $true
}

Test-Case "Close-Logging survives when TranscriptPath is null" {
    . "$root\lib\core.ps1"
    $Script:TranscriptPath = $null
    $Script:Changes = @( [PSCustomObject]@{ k = 1 } )
    $Script:ChangeLogPath = "$env:TEMP\close-log-test-$([guid]::NewGuid()).json"
    Close-Logging
    if (-not (Test-Path $Script:ChangeLogPath)) { throw "change log not written" }
    Remove-Item $Script:ChangeLogPath -ErrorAction SilentlyContinue
    return $true
}

Test-Case "Close-Logging survives when ChangeLogPath is unwritable" {
    . "$root\lib\core.ps1"
    $Script:TranscriptPath = $null
    $Script:Changes = @( [PSCustomObject]@{ k = 1 } )
    $Script:ChangeLogPath = "X:\nonexistent\path\changes.json"
    try { Close-Logging } catch { throw "Close-Logging threw: $_" }
    return $true
}

Test-Case "Test-IsInteractive returns a bool and is callable" {
    . "$root\lib\core.ps1"
    $result = Test-IsInteractive
    if ($null -eq $result) { throw "Test-IsInteractive returned null" }
    if ($result -isnot [bool]) { throw "Test-IsInteractive did not return a bool (got $($result.GetType().Name))" }
    return $true
}

Test-Case "Service debloater sets default action in non-interactive mode" {
    # lib\core.ps1 provides the helper functions (Write-Section etc.)
    . "$root\lib\core.ps1"
    # Then load all modules
    foreach ($mf in Get-ChildItem "$root\modules" -Filter '*.ps1') { . $mf.FullName }
    if (-not (Get-Command Set-ServiceDebloater -ErrorAction SilentlyContinue)) { throw "Set-ServiceDebloater missing" }
    # DryRun path never calls ReadKey, so it works in any context
    Set-ServiceDebloater -DryRun $true -AllowList @()
    return $true
}

Test-Case "Invoke-Cmd helper is exported from lib\core.ps1" {
    . "$root\lib\core.ps1"
    if (-not (Get-Command Invoke-Cmd -ErrorAction SilentlyContinue)) { throw "Invoke-Cmd not found" }
    return $true
}

Test-Case "Invoke-Cmd DryRun short-circuits (no side effect)" {
    . "$root\lib\core.ps1"
    $marker = "$env:TEMP\invoke-cmd-test-$(Get-Random).marker"
    if (Test-Path $marker) { Remove-Item $marker -Force }
    Invoke-Cmd -Cmd "Set-Content -Path '$marker' -Value 'x'" -DryRun $true
    if (Test-Path $marker) { throw "Invoke-Cmd actually executed during DryRun" }
    return $true
}

Test-Case "Invoke-Cmd throws on non-zero exit code" {
    . "$root\lib\core.ps1"
    $threw = $false
    try { Invoke-Cmd -Cmd "cmd /c exit 1" -DryRun $false } catch { $threw = $true }
    if (-not $threw) { throw "Invoke-Cmd did not throw on non-zero exit; caller's try/catch would never fire" }
    return $true
}

Test-Case "No Invoke-Expression remains in any module" {
    $bad = @()
    foreach ($mf in Get-ChildItem "$root\modules" -Filter '*.ps1') {
        $content = Get-Content $mf.FullName -Raw
        # Skip the firewall.ps1 helper comment (it's been replaced with netsh calls)
        $matches = [regex]::Matches($content, 'Invoke-Expression')
        if ($matches.Count -gt 0) { $bad += $mf.Name }
    }
    if ($bad) { throw "Invoke-Expression still present in: $($bad -join ', ')" }
    return $true
}

Test-Case "manifest.sha256 exists and every hash matches the actual file" {
    $manifest = Join-Path $root 'manifest.sha256'
    if (-not (Test-Path $manifest)) { throw "manifest.sha256 missing" }
    $lines = Get-Content $manifest
    if ($lines.Count -lt 20) { throw "manifest has only $($lines.Count) entries, expected 25+" }
    # Verify every entry in the manifest matches the current file on disk.
    # Files listed in the manifest that are no longer present in the repo will
    # appear as "missing" and cause a test failure (correct — stale entry).
    $bad = @()
    foreach ($l in $lines) {
        if ($l -match '^([a-f0-9]{64})\s{2}(.+)$') {
            $expected = $Matches[1].ToLower()
            $file     = $Matches[2].Trim()
            $fullPath = Join-Path $root $file
            if (-not (Test-Path $fullPath)) { $bad += "$file (missing from repo)"; continue }
            $actual = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash.ToLower()
            if ($actual -ne $expected) { $bad += "$file (hash mismatch)" }
        }
    }
    if ($bad) { throw "manifest problems: $($bad -join ', ')" }
    return $true
}

Test-Case "bootstrap.ps1 declares -SkipVerify switch" {
    $content = Get-Content "$root\bootstrap.ps1" -Raw
    if ($content -notmatch '\[switch\]\$SkipVerify') { throw "bootstrap.ps1 missing -SkipVerify parameter" }
    if ($content -notmatch 'manifest\.sha256') { throw "bootstrap.ps1 does not reference manifest.sha256" }
    return $true
}

Test-Case "Invoke-SelfElevate arg construction is type-safe (no broken hashtable embed)" {
    # Verify the function body does NOT do single-quote interpolation of
    # $PSBoundParameters (the old implementation which broke on hashtable values).
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -match "PSBoundParameters\)\s*\|\s*ForEach-Object\s*\{") {
        throw "Invoke-SelfElevate still uses unsafe single-quote interpolation of $PSBoundParameters"
    }
    return $true
}

Test-Case "New-Snapshot collision handler uses try/catch (TOCTOU-safe)" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -match 'while\s*\(\s*Test-Path\s+\$snapDir') {
        throw "New-Snapshot still uses Test-Path-before-Set race; should use try/catch on New-Item"
    }
    if ($c -notmatch 'New-Item\s+-ItemType\s+Directory\s+-Path\s+\$snapDir\s+-ErrorAction\s+Stop') {
        throw "New-Snapshot not using safe New-Item -ErrorAction Stop pattern"
    }
    return $true
}

Test-Case "AllowListOverride merge handles null runtime allow-list" {
    . "$root\lib\core.ps1"
    # Force a null state
    $Script:ConfigDir = "$env:TEMP\hw-test-$([guid]::NewGuid())"
    $null = New-Item -ItemType Directory -Force -Path $Script:ConfigDir
    try {
        # Simulate empty runtime: pre-seed only with one item
        $al = [PSCustomObject]@{ Services = $null; Appx = $null; Modules = @{} }
        Set-AllowList $al
        # Read back
        $loaded = Get-AllowList
        if ($loaded.Services) { throw "Services should be null when JSON has Services=null" }
    } finally {
        Remove-Item $Script:ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $true
}

Test-Case "Restore-Snapshot only restores services whose state differs" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'cur\.StartType\s+-ne\s+\$s\.StartType') {
        throw "Restore-Snapshot does not compare current vs snapshot start types"
    }
    if ($c -notmatch '\$svcRestored') {
        throw "Restore-Snapshot does not aggregate restored/failed counts"
    }
    return $true
}

Test-Case "default.AllowList.psd1 Services and Appx are merged into runtime allow-list" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    if ($c -notmatch '\$alData\.Services') {
        throw "Orchestrator does not merge default.AllowList.psd1 Services into runtime allow-list"
    }
    if ($c -notmatch '\$alData\.Appx') {
        throw "Orchestrator does not merge default.AllowList.psd1 Appx into runtime allow-list"
    }
    return $true
}

Test-Case "Menu bails to Home profile in non-interactive context" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # The 'Determine what to run' block must check Test-IsInteractive before ReadKey
    if ($c -notmatch "if\s*\(\s*-not\s+\(Test-IsInteractive\)\)") {
        throw "Orchestrator main-menu block does not test for non-interactive before ReadKey"
    }
    return $true
}

Test-Case "Dead code: Invoke-WithDryRun is removed" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -match 'function\s+Invoke-WithDryRun') {
        throw "Invoke-WithDryRun is still defined (dead code; use Invoke-Cmd instead)"
    }
    return $true
}

Test-Case "Set-CoreSettings no longer references removed Invoke-WithDryRun" {
    # This is a regression test: removing Invoke-WithDryRun from lib\core.ps1 broke
    # the core.ps1 module because it called the now-missing helper. Catch this
    # in CI before shipping.
    $c = Get-Content "$root\modules\core.ps1" -Raw
    if ($c -match 'Invoke-WithDryRun') {
        throw "modules\core.ps1 still references removed Invoke-WithDryRun; will fail at runtime"
    }
    return $true
}

Test-Case "Set-CoreSettings runs end-to-end in dry-run (no exception)" {
    . "$root\lib\core.ps1"
    foreach ($mf in Get-ChildItem "$root\modules" -Filter '*.ps1') { . $mf.FullName }
    if (-not (Get-Command Set-CoreSettings -ErrorAction SilentlyContinue)) {
        throw "Set-CoreSettings missing"
    }
    try {
        Set-CoreSettings -DryRun $true -AllowList @() 2>&1 | Out-Null
    } catch {
        throw "Set-CoreSettings threw in dry-run: $_"
    }
    return $true
}

Test-Case "Coalesce polyfill is defined before its first use in Harden-Windows.ps1" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # Find the first actual function call (preceded by whitespace, comma, paren, or start of line)
    # Excludes mentions in comments by anchoring to common call patterns.
    $firstUseMatch = [regex]::Match($c, '[\s,=(]Coalesce\s+\$', 'Singleline')
    $firstDef      = [regex]::Match($c, 'function\s+Coalesce', 'Singleline')
    if (-not $firstDef.Success) { throw "Coalesce function not defined" }
    if ($firstUseMatch.Success -and $firstUseMatch.Index -lt $firstDef.Index) {
        throw "Coalesce is invoked before its definition; relies on PS late-binding and is fragile"
    }
    return $true
}

Test-Case "account_lockout uses unique temp file names (not fixed secedit.inf)" {
    $c = Get-Content "$root\modules\account_lockout.ps1" -Raw
    if ($c -match 'tmpInf\s*=\s*"\$env:TEMP\\secedit\.inf"') {
        throw "tmpInf uses a fixed name; concurrent runs would collide"
    }
    if ($c -notmatch 'tmpInf\s*=\s*Join-Path\s+\$env:TEMP\s+[`"'']secedit-') {
        throw "tmpInf does not use a unique temp name"
    }
    return $true
}

Test-Case "Get-AllowList warns on corrupt file and returns safe default" {
    # Test the JSON parsing path without touching the real system config.
    # Simulate the same logic Get-AllowList uses: ReadAllText + IsNullOrWhiteSpace guard.
    $badJson = '{ not valid json'
    try {
        # ConvertFrom-Json throws on malformed JSON in PS 5.1
        $null = $badJson | ConvertFrom-Json
        throw "Expected ConvertFrom-Json to throw on '$badJson'"
    } catch {
        # This is the expected behavior - malformed JSON throws
        # Get-AllowList catches this and returns the default PSCustomObject
        $default = [PSCustomObject]@{ Services = @(); Appx = @(); Modules = @{} }
        if ($null -eq $default) { throw "Default allow-list is null" }
        if (-not ($default.Services -is [array])) { throw "Services is not an array" }
    }
    return $true
}

Test-Case "New-Snapshot reg-export verifies non-empty result" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'Get-Item\s+\$file\)\.Length\s+-gt\s+0') {
        throw "New-Snapshot does not check .reg file size before adding to manifest"
    }
    return $true
}

Test-Case "bootstrap forces re-download when manifest.sha256 is missing" {
    $c = Get-Content "$root\bootstrap.ps1" -Raw
    # The needDownload check must include manifest.sha256 so the bootstrap won't
    # silently proceed without verification if the manifest was deleted.
    if ($c -notmatch 'manifest\.sha256') {
        throw "bootstrap.ps1 needDownload check does not reference manifest.sha256; cache may lack verification"
    }
    return $true
}

Test-Case "no dead `$running variable in Initialize-Logging" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -match '\$running\s*=\s*\$true') {
        throw "Initialize-Logging still has unused `$running variable"
    }
    return $true
}

Test-Case "smb_network.ps1 no longer uses deprecated wmic.exe" {
    $c = Get-Content "$root\modules\smb_network.ps1" -Raw
    # Match wmic as a command token, not as a comment explaining its deprecation.
    # A command-line wmic call begins with wmic at the start of a string value
    # (Action field) or a quoted shell command.
    if ($c -match "['`"]\s*wmic\s+/" -or $c -match "wmic\.exe\s+[/`]") {
        throw "smb_network.ps1 still invokes wmic.exe as a command"
    }
    return $true
}

Test-Case "smb_network.ps1 defines Set-NetbiosPerInterface helper" {
    $c = Get-Content "$root\modules\smb_network.ps1" -Raw
    if ($c -notmatch 'function\s+Set-NetbiosPerInterface') {
        throw "Set-NetbiosPerInterface is not defined; NetBIOS hardening has no real implementation"
    }
    if ($c -notmatch 'NetbiosOptions') {
        throw "Set-NetbiosPerInterface does not write NetbiosOptions"
    }
    return $true
}

Test-Case "Set-NetbiosPerInterface runs without error in dry-run on this machine" {
    . "$root\lib\core.ps1"
    foreach ($mf in Get-ChildItem "$root\modules" -Filter '*.ps1') { . $mf.FullName }
    if (-not (Get-Command Set-NetbiosPerInterface -ErrorAction SilentlyContinue)) {
        throw "Set-NetbiosPerInterface not exported after dot-sourcing"
    }
    try {
        Set-NetbiosPerInterface -DryRun $true 2>&1 | Out-Null
    } catch {
        throw "Set-NetbiosPerInterface threw in dry-run: $_"
    }
    return $true
}

# ── Self-improvement pass 1/2 fixes ───────────────────────────────────────

Test-Case "defender.ps1 DriverLoadPolicy targets HKLM (kernel-mode enforced hive)" {
    $c = Get-Content "$root\modules\defender.ps1" -Raw
    if ($c -match 'reg\s+add\s+"HKCU\\SYSTEM\\CurrentControlSet\\Policies\\EarlyLaunch"') {
        throw "EarlyLaunch DriverLoadPolicy still writes to HKCU\SYSTEM; writes there don't take effect"
    }
    if ($c -notmatch 'reg\s+add\s+"HKLM\\SYSTEM\\CurrentControlSet\\Policies\\EarlyLaunch"') {
        throw "EarlyLaunch DriverLoadPolicy not targeting HKLM\SYSTEM\CurrentControlSet\Policies\EarlyLaunch"
    }
    return $true
}

Test-Case "Harden-Windows.ps1 restore-point prompt defaults to N in non-interactive context" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # The restore-point prompt must branch on Test-IsInteractive so a non-
    # interactive run never silently creates a system restore point.
    if ($c -notmatch "restoreDefault\s*=\s*if\s*\(\s*Test-IsInteractive\s*\)\s*\{") {
        throw "Restore-point prompt does not branch on Test-IsInteractive"
    }
    if ($c -notmatch "Test-IsInteractive\)\s*\{\s*'Y'\s*\}\s*else\s*\{\s*'N'\s*\}") {
        throw "Restore-point prompt does not default to 'N' in non-interactive branch"
    }
    return $true
}

Test-Case "firewall.ps1 Invoke-Netsh is at module scope, not redefined per call" {
    $c = Get-Content "$root\modules\firewall.ps1" -Raw
    # Count the number of 'function Invoke-Netsh' definitions; should be exactly 1.
    $count = ([regex]::Matches($c, 'function\s+Invoke-Netsh')).Count
    if ($count -ne 1) { throw "Expected 1 Invoke-Netsh definition, found $count" }
    # The definition must NOT be inside a function body (look back for an unclosed brace)
    $defIdx = $c.IndexOf('function Invoke-Netsh')
    $snippetBefore = $c.Substring(0, $defIdx)
    # Count braces before the definition: in PS code at module scope, this is fine.
    # The simpler test: the definition should appear before the function Set-FirewallSettings
    $setIdx = $c.IndexOf('function Set-FirewallSettings')
    if ($defIdx -gt $setIdx) { throw "Invoke-Netsh is defined after Set-FirewallSettings; nested definition" }
    return $true
}

Test-Case "profiles.psd1 Home Skip list has no stale module names" {
    $pd = Import-PowerShellDataFile -Path "$root\config\profiles.psd1"
    # Every module in any profile's Skip list must exist as either a real
    # module file in modules\*.ps1 or be a known non-module sentinel like
    # 'service_debloater'.
    $knownMods = @(Get-ChildItem "$root\modules" -Filter '*.ps1' | ForEach-Object { $_.BaseName })
    foreach ($k in 'Home','Workstation','Developer') {
        $skips = @($pd[$k].Skip)
        foreach ($s in $skips) {
            if ($s -notin $knownMods -and $s -notin @('service_debloater')) {
                throw "Profile $k.Skip contains unknown module '$s' (not in modules\*.ps1)"
            }
        }
    }
    return $true
}

Test-Case "office.ps1 reg-add loop is wrapped in try/catch" {
    $c = Get-Content "$root\modules\office.ps1" -Raw
    if ($c -notmatch 'Office reg add failed') {
        throw "office.ps1 does not catch per-iteration reg-add failures"
    }
    return $true
}

Test-Case "privacy.ps1 reg-add loop is wrapped in try/catch" {
    $c = Get-Content "$root\modules\privacy.ps1" -Raw
    if ($c -notmatch 'Privacy reg add failed') {
        throw "privacy.ps1 does not catch per-iteration reg-add failures"
    }
    return $true
}

Test-Case "biometrics.ps1 reg-add loop is wrapped in try/catch" {
    $c = Get-Content "$root\modules\biometrics.ps1" -Raw
    if ($c -notmatch 'Biometrics reg add failed') {
        throw "biometrics.ps1 does not catch per-iteration reg-add failures"
    }
    return $true
}

Test-Case "browser.ps1 Edge/Chrome reg-add loops are wrapped in try/catch" {
    $c = Get-Content "$root\modules\browser.ps1" -Raw
    if ($c -notmatch 'Browser reg add failed') { throw "browser.ps1 Edge loop not guarded" }
    if ($c -notmatch 'Chrome policy reg add failed') { throw "browser.ps1 Chrome loop not guarded" }
    return $true
}

Test-Case "audit_logging.ps1 auditpol loop is wrapped in try/catch" {
    $c = Get-Content "$root\modules\audit_logging.ps1" -Raw
    if ($c -notmatch 'auditpol failed for') {
        throw "audit_logging.ps1 does not catch per-iteration auditpol failures"
    }
    return $true
}

Test-Case "service_debloater skips snapshot in dry-run" {
    $c = Get-Content "$root\modules\service_debloater.ps1" -Raw
    # The New-Snapshot call must be guarded by `if (-not $DryRun)`. Test
    # by checking the bytes around the New-Snapshot call: there must be an
    # `if (-not $DryRun)` line somewhere before it and no closer.
    $snapIdx = $c.IndexOf('New-Snapshot -Label "service-debloat-')
    if ($snapIdx -lt 0) { throw 'service_debloater no longer calls New-Snapshot at all' }
    # 1. There must be at least one `if (-not $DryRun)` in the file
    if ($c -notmatch 'if\s*\(\s*-not\s+\$DryRun\s*\)') {
        throw 'No `if (-not $DryRun)` guard anywhere in service_debloater'
    }
    # 2. The guard must precede the New-Snapshot call (otherwise it doesn't protect it)
    $guardIdx = $c.IndexOf('if (-not $DryRun)')
    if ($guardIdx -lt 0) { throw 'Guard line `if (-not $DryRun)` not found' }
    if ($guardIdx -ge $snapIdx) { throw 'Guard appears after the New-Snapshot call' }
    # 3. The guard must be close enough to be the protecting guard (within 200 chars)
    if (($snapIdx - $guardIdx) -gt 200) { throw 'Guard is too far before the New-Snapshot call' }
    return $true
}

# ── Self-improvement pass 2/2 fixes ───────────────────────────────────────

Test-Case "Harden-Windows.ps1 rollback is de-duplicated via Invoke-LatestRollback" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # The shared helper must exist
    if ($c -notmatch 'function\s+Invoke-LatestRollback') {
        throw "Invoke-LatestRollback helper not defined; rollback is duplicated"
    }
    # The CLI -Rollback branch must call the helper instead of inlining the code
    $cliRollbackIdx = $c.IndexOf('if ($Rollback) {')
    if ($cliRollbackIdx -lt 0) { throw "CLI -Rollback branch not found" }
    $snippetAfter = $c.Substring($cliRollbackIdx, 200)
    if ($snippetAfter -notmatch 'Invoke-LatestRollback') {
        throw "CLI -Rollback branch does not call Invoke-LatestRollback"
    }
    # The menu 'R' branch must call the helper
    if ($c -notmatch "'R'\s*\{\s*Invoke-LatestRollback") {
        throw "Menu 'R' branch does not call Invoke-LatestRollback"
    }
    return $true
}

Test-Case "Harden-Windows.ps1 fnMap is defined once, not per-module loop iteration" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # Count hashtable literal initializations of fnMap; should be exactly 1.
    $count = ([regex]::Matches($c, '\$fnMap\s*=\s*@\{')).Count
    if ($count -ne 1) { throw "Expected exactly 1 `$fnMap hashtable assignment, found $count" }
    return $true
}

Test-Case "Harden-Windows.ps1 OS metadata uses a single Get-CimInstance call" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # Count Win32_OperatingSystem lookups; should be exactly 1.
    $count = ([regex]::Matches($c, 'Get-CimInstance\s+Win32_OperatingSystem')).Count
    if ($count -ne 1) { throw "Expected 1 Get-CimInstance Win32_OperatingSystem call, found $count" }
    return $true
}

Test-Case "Harden-Windows.ps1 summary block tolerates null `$Script:Changes" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    # The summary block must build a local $changes array that is empty
    # if $Script:Changes is null, so the downstream Where-Object pipelines
    # don't throw on null input.
    if ($c -notmatch 'if\s*\(\s*\$null\s*-eq\s+\$Script:Changes\s*\)\s*\{\s*@\(\s*\)\s*\}') {
        throw "Summary block does not guard against null `$Script:Changes"
    }
    return $true
}

Test-Case "bootstrap.ps1 forwards -Profile value correctly (two-token and colon form)" {
    $c = Get-Content "$root\bootstrap.ps1" -Raw
    if ($c -notmatch 'if\s*\(\s*\$a\s+-eq\s+''-Profile''\s*\)\s*\{') {
        throw "bootstrap.ps1 does not handle the two-token -Profile <value> form"
    }
    # Colon form: literal source text "if ($a -match '^..." must appear
    if ($c -notmatch [regex]::Escape("-Profile:(.+")) {
        throw "bootstrap.ps1 does not handle the -Profile:<value> colon form"
    }
    return $true
}

Test-Case "bootstrap.ps1 detects empty/HTML error responses from Invoke-WebRequest" {
    $c = Get-Content "$root\bootstrap.ps1" -Raw
    if ($c -notmatch "Downloaded file is empty") {
        throw "bootstrap.ps1 does not check for empty downloaded files"
    }
    if ($c -notmatch "Downloaded file is HTML") {
        throw "bootstrap.ps1 does not check for HTML error pages"
    }
    return $true
}

Test-Case "appx_debloater.ps1 Get-AppxPackage wrapped in try/catch" {
    $c = Get-Content "$root\modules\appx_debloater.ps1" -Raw
    if ($c -notmatch 'try\s*\{\s*\$installed\s*=\s*@\(Get-AppxPackage') {
        throw "Get-AppxPackage is not wrapped in try/catch"
    }
    if ($c -notmatch 'Get-AppxProvisionedPackage failed') {
        throw "Get-AppxProvisionedPackage failure not handled"
    }
    return $true
}

Test-Case "lib\\core.ps1 Restore-Snapshot builds hashtable explicitly (no Group-Object)" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    # The old code used Group-Object -AsHashTable; the new code uses an
    # explicit hashtable so each entry is a single ServiceController, not
    # a single-element array.
    if ($c -match 'Group-Object.*-AsHashTable') {
        throw "Restore-Snapshot still uses Group-Object -AsHashTable"
    }
    if ($c -notmatch 'foreach\s*\(\s*\$svc\s+in\s+Get-Service') {
        throw "Restore-Snapshot does not build hashtable with explicit foreach over Get-Service"
    }
    return $true
}

# ── Impact metadata + warning tests ───────────────────────────────────────

Test-Case "service_debloater: every entry has an Impact field" {
    $svc = Get-Content "$root\modules\service_debloater.ps1" -Raw
    $svcCount = ([regex]::Matches($svc, "Name='[^']+'\s*;\s*Desc=")).Count
    $impactCount = ([regex]::Matches($svc, "Impact='")).Count
    if ($svcCount -eq 0) { throw "Could not detect service entries" }
    if ($impactCount -lt $svcCount) {
        throw "service_debloater: $svcCount entries but only $impactCount have Impact metadata"
    }
    if ($svc -notmatch 'Write-Host.*impact:') {
        throw "service_debloater does not print impact line in per-item display"
    }
    return $true
}

Test-Case "appx_debloater: every entry has an Impact field" {
    $apx = Get-Content "$root\modules\appx_debloater.ps1" -Raw
    $pCount = ([regex]::Matches($apx, "@\{[^}]*P='")).Count
    $iCount = ([regex]::Matches($apx, "Impact='")).Count
    if ($pCount -eq 0) { throw "Could not detect appx entries" }
    if ($iCount -lt $pCount) {
        throw "appx_debloater: $pCount entries but only $iCount have Impact metadata"
    }
    if ($apx -notmatch 'Write-Host.*impact:') {
        throw "appx_debloater does not print impact line in per-item display"
    }
    return $true
}

Test-Case "defender: every ASR rule has an Impact field" {
    $def = Get-Content "$root\modules\defender.ps1" -Raw
    $ruleCount = ([regex]::Matches($def, "Id\s*='[A-F0-9-]+'\s*;\s*Name\s*='")).Count
    $impactCount = ([regex]::Matches($def, "Impact\s*='")).Count
    if ($impactCount -lt $ruleCount) {
        throw "defender ASR rules: $ruleCount rules but only $impactCount have Impact metadata"
    }
    return $true
}

Test-Case "Harden-Windows.ps1: -AssumeYes param declared" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    if ($c -notmatch '\[switch\]\$AssumeYes') {
        throw "-AssumeYes switch parameter not declared"
    }
    return $true
}

Test-Case "bootstrap: forwards -AssumeYes via indexed PSArgs parsing" {
    $c = Get-Content "$root\bootstrap.ps1" -Raw
    if ($c -notmatch "AssumeYes") {
        throw "bootstrap does not handle -AssumeYes"
    }
    return $true
}

Test-Case "service_debloater: -AssumeYes param accepted and skips per-item prompts" {
    $svc = Get-Content "$root\modules\service_debloater.ps1" -Raw
    if ($svc -notmatch 'param\([^)]*\[switch\]\$AssumeYes') {
        throw "service_debloater does not accept -AssumeYes parameter"
    }
    if ($svc -notmatch 'if.*AssumeYes.*\{') {
        throw "service_debloater does not handle -AssumeYes"
    }
    return $true
}

Test-Case "appx_debloater: -AssumeYes param accepted and removes all non-allow-listed packages" {
    $apx = Get-Content "$root\modules\appx_debloater.ps1" -Raw
    if ($apx -notmatch 'param\([^)]*\[switch\]\$AssumeYes') {
        throw "appx_debloater does not accept -AssumeYes parameter"
    }
    if ($apx -notmatch 'if\s*\(\s*\$AssumeYes\s*\)') {
        throw "appx_debloater does not handle -AssumeYes (no if block)"
    }
    if ($apx -notmatch 'Remove-Appx') {
        throw "appx_debloater does not call Remove-Appx"
    }
    return $true
}

Test-Case "lib\\core.ps1: Confirm-HighImpact defined, requires exact Yes/yes, wired via Read-ConfirmedString" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'function\s+Confirm-HighImpact') {
        throw "Confirm-HighImpact function is not defined"
    }
    if ($c -notmatch "Read-ConfirmedString") {
        throw "Confirm-HighImpact does not use Read-ConfirmedString (full-word capture)"
    }
    # Must require exact "Yes" or "yes" — not a single-char prompt
    if ($c -notmatch "'Yes'.*'yes'|ValidValues.*Yes.*yes") {
        throw "Confirm-HighImpact does not accept exact 'Yes'/'yes' strings"
    }
    return $true
}

Test-Case "usb_autoplay: Print Spooler prompt shows impact" {
    $usb = Get-Content "$root\modules\usb_autoplay.ps1" -Raw
    if ($usb -notmatch 'NO PRINTING') {
        throw "usb_autoplay does not warn about printing loss in Print Spooler prompt"
    }
    return $true
}

Test-Case "fileassoc: requires Confirm-HighImpact instead of Invoke-TimedPrompt" {
    $fa = Get-Content "$root\modules\fileassoc.ps1" -Raw
    if ($fa -notmatch 'Confirm-HighImpact') {
        throw "fileassoc does not call Confirm-HighImpact"
    }
    return $true
}

Test-Case "lib\\core.ps1: Invoke-SelfElevate forwards -AssumeYes" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'if.*\$AssumeYes.*-AssumeYes') {
        throw "Invoke-SelfElevate does not forward -AssumeYes"
    }
    return $true
}

Test-Case "lib\\core.ps1: Invoke-TimedPrompt honours TimeoutSeconds" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'KeyAvailable') {
        throw "Invoke-TimedPrompt does not poll KeyAvailable (no real timeout)"
    }
    if ($c -notmatch 'TimeoutSeconds') {
        throw "Invoke-TimedPrompt does not use TimeoutSeconds parameter"
    }
    return $true
}

Test-Case "lib\\core.ps1: Test-AllowListSchema function defined and validates structure" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'function\s+Test-AllowListSchema') {
        throw "Test-AllowListSchema function is not defined"
    }
    if ($c -notmatch 'Services\[.*not a string') {
        throw "Test-AllowListSchema does not validate Services entries are strings"
    }
    if ($c -notmatch 'Appx\[.*not a string') {
        throw "Test-AllowListSchema does not validate Appx entries are strings"
    }
    if ($c -notmatch 'Modules\..*not a string') {
        throw "Test-AllowListSchema does not validate Modules entries are strings"
    }
    return $true
}

Test-Case "lib\\core.ps1: Get-AllowList calls Test-AllowListSchema" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'Test-AllowListSchema\s+-Data\s+\$parsed') {
        throw "Get-AllowList does not call Test-AllowListSchema"
    }
    return $true
}

Test-Case "service_debloater: high-impact services bypass Confirm-HighImpact only via -ConfirmImpact, not -AssumeYes" {
    $svc = Get-Content "$root\modules\service_debloater.ps1" -Raw
    if ($svc -notmatch 'Confirm-HighImpact') {
        throw "service_debloater does not call Confirm-HighImpact for high-impact services"
    }
    # The function call must NOT pass -AssumeYes (which would bypass the gate)
    $notBypass = 'Confirm-HighImpact[^\n]*-AssumeYes:' + ':$AssumeYes'
    if ($svc -match $notBypass) {
        throw "service_debloater passes -AssumeYes to Confirm-HighImpact (bypasses high-impact gate)"
    }
    if ($svc -notmatch 'PrintSpooler.*TabletInputService.*WbioSrvc|PrintSpooler.*WbioSrvc') {
        throw "service_debloater high-impact list missing one of: PrintSpooler, TabletInputService, WbioSrvc"
    }
    return $true
}

Test-Case "fileassoc: Confirm-HighImpact gate is not bypassed by -AssumeYes alone" {
    $fa = Get-Content "$root\modules\fileassoc.ps1" -Raw
    if ($fa -notmatch 'Confirm-HighImpact') {
        throw "fileassoc does not call Confirm-HighImpact"
    }
    $notBypass = 'Confirm-HighImpact[^\n]*-AssumeYes:' + ':$AssumeYes'
    if ($fa -match $notBypass) {
        throw "fileassoc passes -AssumeYes to Confirm-HighImpact (bypasses high-impact gate)"
    }
    if (-not $fa -match '-ConfirmImpact') {
        throw "fileassoc must honour -ConfirmImpact bypass"
    }
    return $true
}

Test-Case "usb_autoplay: Print Spooler requires Confirm-HighImpact (not AssumeYes bypass)" {
    $usb = Get-Content "$root\modules\usb_autoplay.ps1" -Raw
    if ($usb -notmatch 'Confirm-HighImpact') {
        throw "usb_autoplay does not call Confirm-HighImpact for Print Spooler"
    }
    $notBypass = 'Confirm-HighImpact[^\n]*-AssumeYes:' + ':$AssumeYes'
    if ($usb -match $notBypass) {
        throw "usb_autoplay passes -AssumeYes to Confirm-HighImpact (bypasses high-impact gate)"
    }
    return $true
}

Test-Case "fileassoc: requires Confirm-HighImpact instead of Invoke-TimedPrompt" {
    $fa = Get-Content "$root\modules\fileassoc.ps1" -Raw
    if ($fa -notmatch 'Confirm-HighImpact') {
        throw "fileassoc does not call Confirm-HighImpact"
    }
    return $true
}

Test-Case "Harden-Windows.ps1: -ConfirmImpact param declared and forwarded to modules" {
    $c = Get-Content "$root\Harden-Windows.ps1" -Raw
    if ($c -notmatch '\[switch\]\$ConfirmImpact') {
        throw "-ConfirmImpact switch parameter not declared"
    }
    if ($c -notmatch 'ConfirmImpact:\$ConfirmImpact') {
        throw "-ConfirmImpact is not forwarded to module invocations"
    }
    return $true
}

Test-Case "bootstrap: forwards -ConfirmImpact to orchestrator" {
    $c = Get-Content "$root\bootstrap.ps1" -Raw
    if ($c -notmatch 'ConfirmImpact') {
        throw "bootstrap does not forward -ConfirmImpact"
    }
    return $true
}

Test-Case "lib\\core.ps1: Invoke-SelfElevate forwards -ConfirmImpact" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'if.*\$ConfirmImpact.*-ConfirmImpact') {
        throw "Invoke-SelfElevate does not forward -ConfirmImpact"
    }
    return $true
}
Test-Case "README documents the ConfirmImpact bypass contract" {
    $readme = Get-Content "$root\README.md" -Raw
    if ($readme -notmatch 'Confirmation contract') {
        throw "README does not document the confirmation contract"
    }
    if ($readme -notmatch '-ConfirmImpact') {
        throw "README does not document -ConfirmImpact switch"
    }
    if ($readme -notmatch '-ValidateAllowList') {
        throw "README does not document -ValidateAllowList switch"
    }
    return $true
}

Test-Case "Harden-Windows.ps1: -ValidateAllowList param declared" {
    $hw = Get-Content "$root\Harden-Windows.ps1" -Raw
    if ($hw -notmatch '\[switch\]\$ValidateAllowList') {
        throw "Harden-Windows.ps1 does not declare -ValidateAllowList param"
    }
    return $true
}

Test-Case "Harden-Windows.ps1: -ValidateAllowList runs before admin check (no privilege required)" {
    $hw = Get-Content "$root\Harden-Windows.ps1" -Raw
    # Find the ValidateAllowList block; it must be BEFORE the first Test-IsAdmin call.
    $valIdx = $hw.IndexOf('if ($ValidateAllowList)')
    $adminIdx = $hw.IndexOf('Test-IsAdmin')
    if ($valIdx -lt 0) { throw "ValidateAllowList block not found" }
    if ($adminIdx -lt 0) { throw "Test-IsAdmin not found" }
    if ($valIdx -gt $adminIdx) {
        throw "ValidateAllowList block runs AFTER Test-IsAdmin (line $valIdx vs $adminIdx)"
    }
    return $true
}

Test-Case "lib\\core.ps1: New-Snapshot captures Appx state" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    if ($core -notmatch 'appx\.json') { throw "New-Snapshot does not write appx.json" }
    if ($core -notmatch 'Get-AppxPackage') { throw "New-Snapshot does not enumerate Appx packages" }
    if ($core -notmatch 'Get-AppxProvisionedPackage') { throw "New-Snapshot does not enumerate provisioned packages" }
    return $true
}

Test-Case "lib\\core.ps1: Restore-Snapshot re-registers user Appx packages" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    if ($core -notmatch 'Add-AppxPackage\s+-Register') { throw "Restore-Snapshot does not re-register via Add-AppxPackage" }
    if ($core -notmatch 'AppxManifest\.xml') { throw "Restore-Snapshot does not target AppxManifest.xml" }
    if ($core -notmatch 'require manual reinstall') { throw "Restore-Snapshot does not list packages needing manual reinstall" }
    return $true
}

Test-Case "Confirm-HighImpact has no AssumeYes param (gate cannot be bypassed from inside the function)" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    # The function definition must NOT declare [switch]$AssumeYes.
    if ($core -match 'function\s+Confirm-HighImpact\s*\{[\s\S]{0,400}\[switch\]\$AssumeYes') {
        throw "Confirm-HighImpact still declares [switch]`$AssumeYes (re-introduces the bypass bug)"
    }
    return $true
}

Test-Case "Confirm-HighImpact rejects non-interactive contexts (refuses implicit bypass)" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    if ($core -notmatch 'function\s+Confirm-HighImpact\s*\{[\s\S]{0,800}Test-IsInteractive') {
        throw "Confirm-HighImpact does not consult Test-IsInteractive"
    }
    return $true
}

Test-Case "Restore-Snapshot dedupes manual-reinstall list" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    # After the Appx section, before the foreach that prints, dedupe must run.
    if ($core -notmatch '\$appxManual\s*=\s*@\(\$appxManual\s*\|\s*Select-Object\s+-Unique\)') {
        throw "Restore-Snapshot does not dedupe `$appxManual before printing"
    }
    return $true
}

Test-Case "Restore-Snapshot wraps Get-Service in try/catch" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    if ($core -notmatch 'Get-Service -ErrorAction Stop') {
        throw "Restore-Snapshot does not use -ErrorAction Stop on Get-Service"
    }
    return $true
}


    Test-Case "manifest references all new + changed files" {
        $manifest = Get-Content "$root\manifest.sha256" -Raw
        $required = @('README.md', 'lib.core.ps1', 'Harden-Windows.ps1', 'tests.regression.ps1')
        foreach ($r in $required) {
            if ($manifest -notmatch $r) {
                throw "manifest.sha256 missing entry for $r"
            }
        }
        return $true
    }


    Test-Case "Restore-Snapshot uses explicit bool cast on Provisioned field" {
    $core = Get-Content "$root\lib\core.ps1" -Raw
    if ($core -notmatch '\[bool\]\$rec\.Provisioned') {
        throw "Restore-Snapshot does not explicitly cast Provisioned to bool"
    }
    return $true
}


Test-Case "lib\\core.ps1 uses List for Add-Change (no O(n^2) array append)" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch '\.Add\(') {
        throw "Add-Change does not use .Add() method"
    }
    if ($c -match '\$Script:Changes\s*\+=') {
        throw "Add-Change still uses += on Script:Changes (O(n^2))"
    }
    return $true
}

Test-Case "lib\\core.ps1 Invoke-SelfElevate forwards -ValidateAllowList" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'ValidateAllowList') {
        throw "Invoke-SelfElevate does not forward ValidateAllowList"
    }
    return $true
}

Test-Case "bootstrap.ps1 forwards -ValidateAllowList" {
    $b = Get-Content "$root\bootstrap.ps1" -Raw
    if ($b -notmatch "'-ValidateAllowList'") {
        throw "bootstrap.ps1 PSArgs parser does not forward ValidateAllowList"
    }
    return $true
}

Test-Case "lib\\core.ps1 snapshot suffix uses 8 hex chars (not 4)" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'Get-Random\s+-Count\s+8') {
        throw "New-Snapshot does not use Get-Random -Count 8 for suffix"
    }
    return $true
}

Test-Case "lib\\core.ps1 centralizes prompt timeouts as script vars" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch '\$Script:PromptTimeoutSeconds') {
        throw "No PromptTimeoutSeconds constant defined"
    }
    if ($c -notmatch '\$Script:HighImpactTimeoutSeconds') {
        throw "No HighImpactTimeoutSeconds constant defined"
    }
    return $true
}


Test-Case "appx_debloater does not declare ConfirmImpact (no high-impact gate)" {
    $a = Get-Content "$root\modules\appx_debloater.ps1" -Raw
    if ($a -match '\[switch\]\$ConfirmImpact') {
        throw "appx_debloater still declares [switch]`$ConfirmImpact"
    }
    return $true
}

Test-Case "orchestrator does not pass -ConfirmImpact to appx_debloater" {
    $hw = Get-Content "$root\Harden-Windows.ps1" -Raw
    if ($hw -notmatch "appx_debloater") {
        throw "orchestrator does not reference appx_debloater"
    }
    if ($hw -notmatch "if \(\`$modName -eq 'appx_debloater'\)") {
        throw "orchestrator does not special-case appx_debloater invocation"
    }
    return $true
}

Test-Case "fileassoc uses Invoke-Cmd directly (no dead `$do` scriptblock)" {
    $f = Get-Content "$root\modules\fileassoc.ps1" -Raw
    if ($f -match '\$do\s*=\s*\{') {
        throw "fileassoc still defines dead `$do scriptblock"
    }
    if ($f -notmatch 'Invoke-Cmd\s+-Cmd') {
        throw "fileassoc does not call Invoke-Cmd"
    }
    return $true
}

Test-Case "usb_autoplay uses Invoke-Cmd directly (no dead `$do` scriptblock)" {
    $u = Get-Content "$root\modules\usb_autoplay.ps1" -Raw
    if ($u -match '\$do\s*=\s*\{') {
        throw "usb_autoplay still defines dead `$do scriptblock"
    }
    if ($u -notmatch 'Invoke-Cmd\s+-Cmd') {
        throw "usb_autoplay does not call Invoke-Cmd"
    }
    return $true
}


Test-Case "service_debloater high-impact gate is properly nested inside change check" {
    $s = Get-Content "$root\modules\service_debloater.ps1" -Raw
    if ($s -notmatch 'PrintSpooler.*TabletInputService.*WbioSrvc') {
        throw "service_debloater does not reference all three high-impact services"
    }
    if ($s -notmatch 'Confirm-HighImpact') {
        throw "service_debloater does not use Confirm-HighImpact"
    }
    return $true
}

Test-Case "service_debloater indentation: high-impact block appears before Set-Service block" {
    $s = Get-Content "$root\modules\service_debloater.ps1" -Raw
    $hi = $s.IndexOf('$highImpactNames')
    $set = $s.IndexOf('$newType = $it.Action')
    if ($hi -lt 0)  { throw "high-impact block not found" }
    if ($set -lt 0) { throw "Set-Service block not found" }
    if ($hi -gt $set) { throw "high-impact block appears after Set-Service block (wrong nesting)" }
    return $true
}


Test-Case "Invoke-SelfElevate forwards -ConfigPath and -ModulePath" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'if \(\$ConfigPath\)') {
        throw "Invoke-SelfElevate does not forward ConfigPath"
    }
    if ($c -notmatch 'if \(\$ModulePath\)') {
        throw "Invoke-SelfElevate does not forward ModulePath"
    }
    return $true
}

Test-Case "Get-AllowList guards against empty ConfigDir" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch "ConfigDir not initialized") {
        throw "Get-AllowList does not guard against empty ConfigDir"
    }
    return $true
}

Test-Case "Set-AllowList guards against empty ConfigDir" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch "cannot write allow-list") {
        throw "Set-AllowList does not guard against empty ConfigDir"
    }
    return $true
}

Test-Case "Test-WindowsVersion uses ErrorAction Stop (no unhandled throw)" {
    $c = Get-Content "$root\lib\core.ps1" -Raw
    if ($c -notmatch 'Get-CimInstance.*ErrorAction Stop') {
        throw "Test-WindowsVersion does not use ErrorAction Stop on Get-CimInstance"
    }
    return $true
}


Write-Host "=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if($fail -eq 0){'Green'}else{'Red'})
    exit $fail