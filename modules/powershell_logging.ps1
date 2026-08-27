# powershell_logging.ps1 -- Scriptblock/Module logging, transcription, execution policy
$Module = 'powershell_logging'

function Set-PowerShellLogging {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "PowerShell logging & execution"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    if ($AllowList -notcontains 'SkipExecPolicy') {
        & $do 'powershell.exe -NoProfile -Command "Set-ExecutionPolicy RemoteSigned -Force"'
        Add-Change $Module 'ExecutionPolicy' '?' 'RemoteSigned' $(if($DryRun){'DRY'}else{'OK'})
    }

    # Script block logging
    & $do 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging" /v EnableScriptBlockLogging /t REG_DWORD /d 1 /f'
    # Module logging
    & $do 'reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging" /v EnableModuleLogging /t REG_DWORD /d 1 /f'

    # PowerShell v2 (engine + root) - see also modules\powershell_v2.ps1
    Add-Change $Module 'ScriptBlockLogging' 'unset' 'enabled' $(if($DryRun){'DRY'}else{'OK'})
    Add-Change $Module 'ModuleLogging' 'unset' 'enabled' $(if($DryRun){'DRY'}else{'OK'})

    Write-Pass "PowerShell logging configured."
}

