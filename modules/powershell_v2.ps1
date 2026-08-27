# powershell_v2.ps1 -- Remove PowerShell v2 (full downgrade attack mitigation)
$Module = 'powershell_v2'

function Set-PowerShellV2 {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "PowerShell v2 removal"

    if ($AllowList -contains 'KeepPSv2') {
        Write-Skip "PSv2 kept by allow-list."
        return
    }
    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }
    & $do 'powershell.exe -NoProfile -Command "Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2 -norestart"'
    & $do 'powershell.exe -NoProfile -Command "Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -norestart"'
    Add-Change $Module 'PowerShellV2' 'enabled' 'disabled' $(if($DryRun){'DRY'}else{'OK'})
    Write-Pass "PowerShell v2 engine disabled."
}

