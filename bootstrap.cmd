@echo off
:: Harden-Windows one-line installer (cmd flavor of bootstrap.ps1)
:: Designed for:  curl -L -o %TEMP%\h.cmd https://raw.githubusercontent.com/neohiro/windows/main/bootstrap.cmd && %TEMP%\h.cmd Home
::
::   bootstrap.cmd                — interactive menu
::   bootstrap.cmd Home           — Home profile, no prompt
::   bootstrap.cmd Workstation    — Workstation profile, no prompt
::   bootstrap.cmd Home -Update   — force re-download
::   bootstrap.cmd Home -DryRun   — preview
::   bootstrap.cmd Rollback       — restore last session
:: ================================================================

setlocal enabledelayedexpansion

set "PS_BOOT=%~dp0bootstrap.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: ── Admin check ─────────────────────────────────────────────────────────
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!!] Not elevated. Re-launching as administrator...
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c cd /d %CD% ^&^& %~nx0 %*' -Verb RunAs"
    exit /b
)

:: ── Detect local file vs remote one-liner ───────────────────────────────
:: If this .cmd is running from %TEMP% (downloaded), bootstrap.ps1 was
:: fetched alongside it. Otherwise (developer runs the repo copy), pass
:: PS_BOOT as the repo's own bootstrap.ps1.
if not exist "%PS_BOOT%" (
    :: Standalone mode: download bootstrap.ps1 to a temp dir and invoke
    set "TMPDIR=%TEMP%\HardenWindows-%RANDOM%"
    mkdir "!TMPDIR!" >nul 2>&1
    powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%~dpn0.ps1' -OutFile '!TMPDIR!\bootstrap.ps1' -UseBasicParsing -ErrorAction Stop } catch { Write-Host 'Failed to download bootstrap.ps1: $_'; exit 1 }"
    if not exist "!TMPDIR!\bootstrap.ps1" (
        echo [!!] Could not obtain bootstrap.ps1
        exit /b 1
    )
    set "PS_BOOT=!TMPDIR!\bootstrap.ps1"
)

:: ── Build PS args ──────────────────────────────────────────────────────
set "PS_ARGS=-NoProfile -ExecutionPolicy Bypass -File "%PS_BOOT%""

:parse
if "%~1"=="" goto :done_parsing
if /i "%~1"=="Home"          set "PS_ARGS=%PS_ARGS% -Profile Home"
if /i "%~1"=="Workstation"   set "PS_ARGS=%PS_ARGS% -Profile Workstation"
if /i "%~1"=="Developer"     set "PS_ARGS=%PS_ARGS% -Profile Developer"
if /i "%~1"=="Custom"        set "PS_ARGS=%PS_ARGS% -Profile Custom"
if /i "%~1"=="-Update"       set "PS_ARGS=%PS_ARGS% -Update"
if /i "%~1"=="-DryRun"       set "PS_ARGS=%PS_ARGS% -PSArgs -DryRun"
if /i "%~1"=="-SkipDebloat"  set "PS_ARGS=%PS_ARGS% -PSArgs -SkipDebloat"
if /i "%~1"=="-Rollback"     set "PS_ARGS=%PS_ARGS% -PSArgs -Rollback"
shift
goto :parse

:done_parsing
echo.
echo ############################################################
echo #  Harden-Windows bootstrap (cmd)
echo #  Invoking: %POWERSHELL% %PS_ARGS%
echo ############################################################
echo.

%POWERSHELL% %PS_ARGS%
exit /b %errorlevel%
