@echo off
:: Harden-Windows one-command launcher
:: Usage:
::   harden.cmd                  - interactive menu
::   harden.cmd Home            - Home profile (safe defaults)
::   harden.cmd Workstation     - hardened office workstation (STIG-lite)
::   harden.cmd Developer       - developer profile
::   harden.cmd DryRun          - preview changes (no writes)
::   harden.cmd Rollback        - restore last snapshot
::   harden.cmd SkipDebloat    - skip interactive debloaters
::   harden.cmd -ConfirmImpact - bypass typed Yes/yes gate (CI/automation)
::   harden.cmd -AssumeYes     - accept non-destructive prompts (not high-impact gates)
::   harden.cmd -ValidateAllowList - validate JSON allow-list and exit
::   harden.cmd -help          - show this help
:: ================================================================

setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Harden-Windows.ps1"
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: -- Parse arguments ----------------------------------------------------------
set "PROFILE_ARG="
set "DRY_RUN="
set "ROLLBACK="
set "SKIP_DEBLOAT="
set "CONFIRM_IMPACT="
set "ASSUME_YES="
set "VALIDATE_ALLOWLIST="
set "SHOW_HELP="

:parse
if "%~1"=="" goto :done_parsing
set "arg=%~1"
if /i "%arg%"=="-profile"       ( set "PROFILE_ARG=%~2"& shift & shift & goto :parse )
if /i "%arg%"=="Home"            ( set "PROFILE_ARG=Home"&          shift & goto :parse )
if /i "%arg%"=="Workstation"     ( set "PROFILE_ARG=Workstation"&   shift & goto :parse )
if /i "%arg%"=="Developer"       ( set "PROFILE_ARG=Developer"&     shift & goto :parse )
if /i "%arg%"=="DryRun"          ( set "DRY_RUN=-DryRun"&         shift & goto :parse )
if /i "%arg%"=="Rollback"        ( set "ROLLBACK=-Rollback"&       shift & goto :parse )
if /i "%arg%"=="SkipDebloat"     ( set "SKIP_DEBLOAT=-SkipDebloat"&shift & goto :parse )
if /i "%arg%"=="-DryRun"         ( set "DRY_RUN=-DryRun"&         shift & goto :parse )
if /i "%arg%"=="-Rollback"       ( set "ROLLBACK=-Rollback"&       shift & goto :parse )
if /i "%arg%"=="-SkipDebloat"    ( set "SKIP_DEBLOAT=-SkipDebloat"&shift & goto :parse )
if /i "%arg%"=="-ConfirmImpact"  ( set "CONFIRM_IMPACT=-ConfirmImpact"&shift & goto :parse )
if /i "%arg%"=="-AssumeYes"      ( set "ASSUME_YES=-AssumeYes"&     shift & goto :parse )
if /i "%arg%"=="-ValidateAllowList" ( set "VALIDATE_ALLOWLIST=-ValidateAllowList"&shift & goto :parse )
if /i "%arg%"=="-h"             ( set "SHOW_HELP=1"&            shift & goto :parse )
if /i "%arg%"=="-help"          ( set "SHOW_HELP=1"&            shift & goto :parse )
shift
goto :parse

:done_parsing

:: -- Help (must exit before the admin check so help works without elevation) --
if defined SHOW_HELP (
    echo.
    echo Harden-Windows  -  One-command Windows hardening
    echo.
    echo Usage: %~nx0 [Profile] [Options]
    echo.
    echo Profiles:
    echo   Home           Privacy + security baseline (safe for family PCs)
    echo   Workstation    Hardened office workstation (STIG-lite)
    echo   Developer      Keeps PS remoting, dev tools
    echo   [none]        Interactive menu
    echo.
    echo Options:
    echo   -DryRun        Preview all changes (no writes)
    echo   -Rollback      Restore last session snapshot
    echo   -SkipDebloat   Skip interactive debloaters
    echo   -ConfirmImpact Bypass typed "Yes"/"yes" gate for high-impact actions (CI)
    echo   -AssumeYes     Accept non-destructive prompts (does NOT bypass high-impact)
    echo   -ValidateAllowList  Validate allow-list JSON and exit (no changes)
    echo.
    echo Examples:
    echo   %~nx0                        - interactive menu
    echo   %~nx0 Home                   - Home profile
    echo   %~nx0 Workstation DryRun     - preview workstation hardening
    echo   %~nx0 Rollback               - restore previous state
    echo.
    echo Allow-lists:
    echo   Edit: %%ProgramData%%\HardenWindows\Config\allowlist.json
    echo         (or %%PROGRAMDATA%%\HardenWindows\Config\default.AllowList.psd1)
    echo.
    echo Logs: %%ProgramData%%\HardenWindows\Logs\
    echo.
    exit /b 0
)

:: -- Admin check --------------------------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [!!] Not running as Administrator. Re-launching elevated...
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c cd /d %CD% ^&^& %~nx0 %*' -Verb RunAs"
    exit /b
)

:: -- Build PowerShell args ---------------------------------------------------
set "PS_ARGS=-NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%""

if defined PROFILE_ARG      set "PS_ARGS=%PS_ARGS% -Profile %PROFILE_ARG%"
if defined DRY_RUN         set "PS_ARGS=%PS_ARGS% %DRY_RUN%"
if defined ROLLBACK        set "PS_ARGS=%PS_ARGS% %ROLLBACK%"
if defined SKIP_DEBLOAT    set "PS_ARGS=%PS_ARGS% %SKIP_DEBLOAT%"
if defined CONFIRM_IMPACT   set "PS_ARGS=%PS_ARGS% %CONFIRM_IMPACT%"
if defined ASSUME_YES       set "PS_ARGS=%PS_ARGS% %ASSUME_YES%"
if defined VALIDATE_ALLOWLIST set "PS_ARGS=%PS_ARGS% %VALIDATE_ALLOWLIST%"

:: -- Banner ------------------------------------------------------------------
cls
echo.
echo ################################################################
echo  #  HARDEN-WINDOWS  -  neohiro/windows
echo  #  One-command: double-click or run from elevated CMD
echo ################################################################
echo.
echo  Profile  : %PROFILE_ARG%
echo  Dry run  : %DRY_RUN%
echo  Rollback : %ROLLBACK%
echo.

:: -- Launch ------------------------------------------------------------------
%POWERSHELL% %PS_ARGS%
set "EXIT_CODE=%errorlevel%"

if %EXIT_CODE% neq 0 (
    echo.
    echo [!!] PowerShell exited with code %EXIT_CODE%
    pause
)
exit /b %EXIT_CODE%
