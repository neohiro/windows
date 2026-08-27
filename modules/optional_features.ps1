# optional_features.ps1 -- Disable optional features with allow-list
$Module = 'optional_features'

$Features = @(
    @{ F='SMB1Protocol'; Key='DisableSMB1' }
    @{ F='MicrosoftWindowsPowerShellV2'; Key='KeepPSv2' }
    @{ F='WorkFolders-Client'; Key='DisableWorkFolders' }
    @{ F='Printing-XPSServices-Features'; Key='DisableXPS' }
    @{ F='Internet-Explorer-Optional-amd64'; Key='DisableIE' }
)

function Set-OptionalFeatures {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Optional Windows Features"

    foreach ($f in $Features) {
        $skipKey = switch ($f.Key) {
            'KeepPSv2'         { 'KeepPSv2' }
            'DisableSMB1'      { 'DisableSMB1' }
            default            { "Disable_$($f.F)" }
        }
        if ($AllowList -contains $skipKey) {
            Write-Skip "Feature allow-listed: $($f.F)"
            Add-Change $Module "feature:$($f.F)" 'enabled' 'ALLOWED' 'SKIP'
            continue
        }
        $cmd = "powershell.exe -NoProfile -Command `"Disable-WindowsOptionalFeature -Online -FeatureName $($f.F) -NoRestart -ErrorAction SilentlyContinue`""
        if ($DryRun) { Write-Info "DRY-RUN: $cmd"; Add-Change $Module "feature:$($f.F)" 'enabled' 'preview' 'DRY' }
        else {
            try { Invoke-Cmd -Cmd $cmd -DryRun $DryRun; Add-Change $Module "feature:$($f.F)" 'enabled' 'disabled' 'OK' }
            catch { Add-Change $Module "feature:$($f.F)" 'enabled' 'errored' 'ERR' }
        }
    }
    Write-Pass "Optional features processed."
}

