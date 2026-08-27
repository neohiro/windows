# appx_debloater.ps1 -- Interactive Appx debloater with allow-list
$Module = 'appx_debloater'

# Default catalog. Items with a wildcard pattern match the installed package name.
$DefaultAppx = @(
    'Microsoft.BingWeather','Microsoft.GetHelp','Microsoft.Getstarted',
    'Microsoft.Messaging','Microsoft.MicrosoftOfficeHub','Microsoft.OneConnect',
    'Microsoft.People','Microsoft.Print3D','Microsoft.SkypeApp',
    'Microsoft.Wallet','Microsoft.WindowsAlarms','Microsoft.WindowsCamera',
    'microsoft.windowscommunicationsapps','Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps','Microsoft.WindowsSoundRecorder','Microsoft.YourPhone',
    'Microsoft.WindowsFeedback','Windows.ContactSupport','PandoraMedia*',
    'AdobeSystemIncorporated.AdobePhotoshopExpress*','Duolingo*','Microsoft.BingNews',
    'Microsoft.Office.Sway','Microsoft.Advertising.Xaml*','ActiproSoftware*',
    'EclipseManager*','SpotifyAB.SpotifyMusic*','king.com.*',
    'Microsoft.549981C3F5F10','Microsoft.Microsoft3DViewer','Microsoft.MSPaint',
    'Microsoft.OneNote','Microsoft.PowerAutomateDesktop','Microsoft.Todos',
    'Microsoft.MixedReality.Portal','Microsoft.ScreenSketch'
)

function Set-AppxDebloater {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Appx Package Debloater (interactive)"

    if ($AllowList -contains 'KeepAllAppx') {
        Write-Skip "Appx removal skipped (allow-list)."
        return
    }

    $installed = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    $candidates = @()
    foreach ($p in $DefaultAppx) {
        $matches = $installed | Where-Object { $_.Name -like $p }
        foreach ($m in $matches) {
            $allowMatch = $AllowList | Where-Object { $m.Name -like $_ }
            $candidates += [PSCustomObject]@{
                Name        = $m.Name
                FullName    = $m.PackageFullName
                Provisioned = $false
                AllowListed = [bool]$allowMatch
            }
        }
    }

    # Provisioned too
    $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    foreach ($p in $DefaultAppx) {
        $matches = $prov | Where-Object { $_.DisplayName -like $p }
        foreach ($m in $matches) {
            $candidates += [PSCustomObject]@{
                Name        = $m.DisplayName
                FullName    = $m.PackageName
                Provisioned = $true
                AllowListed = $AllowList -contains $m.DisplayName
            }
        }
    }

    $candidates = $candidates | Sort-Object -Property Name -Unique
    if (-not $candidates) { Write-Info "No matching Appx packages found."; return }

    $defaultRemove = 'Y'
    $index = 0
    while ($index -lt $candidates.Count) {
        $c = $candidates[$index]
        $tag = if ($c.Provisioned) { '[PROV]' } else { '[USER]' }
        $al  = if ($c.AllowListed) { '[ALLOW-LISTED]' } else { '' }
        Write-Host ""
        Write-Host ("[{0,2}/{1,-2}] {2}  {3}  {4}" -f ($index+1), $candidates.Count, $c.Name, $tag, $al) -ForegroundColor $(if($c.AllowListed){'DarkGray'}else{'White'})

        if ($c.AllowListed) { $index++; continue }

        $resp = Invoke-TimedPrompt -Message "  Remove? [Y=Yes, N=No, S=Skip rest, A=Allow-list this one]" -Default $defaultRemove -ValidChars @('Y','N','S','A')
        switch ($resp) {
            'Y' {
                $do = if ($c.Provisioned) {
                    { Remove-AppxProvisionedPackage -Online -PackageName $c.FullName -ErrorAction Stop }
                } else {
                    { Remove-AppxPackage -Package $c.FullName -AllUsers -ErrorAction Stop }
                }
                if ($DryRun) { Write-Info "DRY-RUN: remove $($c.Name)"; Add-Change $Module "appx:$($c.Name)" 'installed' 'preview-removed' 'DRY' }
                else {
                    try { & $do; Add-Change $Module "appx:$($c.Name)" 'installed' 'removed' 'OK' }
                    catch { Write-Warn "  Failed: $_"; Add-Change $Module "appx:$($c.Name)" 'installed' 'failed' 'ERR' }
                }
            }
            'A' {
                $alObj = Get-AllowList
                $existing = @($alObj.Appx) | Where-Object { $_ -and ($_ -is [string]) }
                $existing += $c.Name
                $alObj.Appx = $existing | Select-Object -Unique
                Set-AllowList $alObj
                Write-Pass "  Added '$($c.Name)' to allow-list."
            }
            'N' { Add-Change $Module "appx:$($c.Name)" 'installed' 'kept' 'SKIP' }
            'S' { Write-Info "Stopping."; return }
        }
        $index++
    }

    Write-Pass "Appx debloat complete."
}

