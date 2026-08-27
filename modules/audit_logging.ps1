# audit_logging.ps1 -- Event log sizing, advanced audit policy
$Module = 'audit_logging'

function Set-AuditLogging {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Advanced audit & event log sizing"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    # Event log size
    foreach ($log in 'Security','Application','System','Windows Powershell','Microsoft-Windows-PowerShell/Operational') {
        & $do "wevtutil sl `"$log`" /ms:1024000"
    }

    # 4688 with command line
    & $do 'reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit" /v ProcessCreationIncludeCmdLine_Enabled /t REG_DWORD /d 1 /f'
    # Force advanced audit policy
    & $do 'reg add "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" /v SCENoApplyLegacyAuditPolicy /t REG_DWORD /d 1 /f'

    # Audit subcategories
    $auditPol = @(
        @{ Sub='Security Group Management';   S='enable'; F='enable' }
        @{ Sub='Process Creation';             S='enable'; F='enable' }
        @{ Sub='Logoff';                       S='enable'; F='disable' }
        @{ Sub='Logon';                        S='enable'; F='enable' }
        @{ Sub='Filtering Platform Connection';S='enable'; F='disable' }
        @{ Sub='Removable Storage';            S='enable'; F='enable' }
        @{ Sub='IPsec Driver';                 S='enable'; F='enable' }
        @{ Sub='Security State Change';        S='enable'; F='enable' }
        @{ Sub='Security System Extension';    S='enable'; F='enable' }
        @{ Sub='System Integrity';             S='enable'; F='enable' }
    )
    foreach ($a in $auditPol) {
        & $do "Auditpol /set /subcategory:`"$($a.Sub)`" /success:$($a.S) /failure:$($a.F)"
    }

    Add-Change $Module 'EventLogSize' '51200' '1024000' $(if($DryRun){'DRY'}else{'OK'})
    Add-Change $Module 'ProcessCreation4688' 'off' 'on' $(if($DryRun){'DRY'}else{'OK'})
    Add-Change $Module 'AdvancedAuditPolicy' 'off' 'on' $(if($DryRun){'DRY'}else{'OK'})
    Write-Pass "Audit policy + log sizing applied."
}

