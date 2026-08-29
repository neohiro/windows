# appx_debloater.ps1 -- Interactive Appx debloater with allow-list
$Module = 'appx_debloater'

# Default catalog. Items with a wildcard pattern match the installed package name.
# Impact describes the USER-FACING ABILITY lost when the package is removed.
# These are surfaced in the per-item prompt and in the README impact table.
$DefaultAppx = @(
    @{ P='Microsoft.BingWeather';                  Impact='No built-in Weather tile or app' }
    @{ P='Microsoft.GetHelp';                      Impact='No "Get Help" app' }
    @{ P='Microsoft.Getstarted';                   Impact='No "Tips" / Get started welcome' }
    @{ P='Microsoft.Messaging';                    Impact='No built-in Messaging app (SMS)' }
    @{ P='Microsoft.MicrosoftOfficeHub';           Impact='No My Office hub' }
    @{ P='Microsoft.OneConnect';                   Impact='No Mobile Plans / data usage app' }
    @{ P='Microsoft.People';                       Impact='No People app (contacts)' }
    @{ P='Microsoft.Print3D';                      Impact='No 3D printing (rarely used)' }
    @{ P='Microsoft.SkypeApp';                     Impact='No preinstalled Skype (Microsoft retiring it; use your own client)' }
    @{ P='Microsoft.Wallet';                       Impact='No Microsoft Wallet app' }
    @{ P='Microsoft.WindowsAlarms';                Impact='No Alarms & Clock app' }
    @{ P='Microsoft.WindowsCamera';                Impact='No built-in Camera app (webcam not usable from this app)' }
    @{ P='microsoft.windowscommunicationsapps';    Impact='No Mail/Calendar combined package' }
    @{ P='Microsoft.WindowsFeedbackHub';           Impact='No Feedback Hub (some diagnostic data flow affected)' }
    @{ P='Microsoft.WindowsMaps';                  Impact='No Maps app' }
    @{ P='Microsoft.WindowsSoundRecorder';         Impact='No Voice Recorder app' }
    @{ P='Microsoft.YourPhone';                    Impact='No Phone Link / Your Phone companion (no PC-phone integration)' }
    @{ P='Microsoft.WindowsFeedback';              Impact='No Feedback Hub legacy component' }
    @{ P='Windows.ContactSupport';                  Impact='No Contact Support app' }
    @{ P='PandoraMedia*';                          Impact='Preinstalled Pandora app removed' }
    @{ P='AdobeSystemIncorporated.AdobePhotoshopExpress*'; Impact='Preinstalled Photoshop Express removed' }
    @{ P='Duolingo*';                              Impact='Preinstalled Duolingo removed' }
    @{ P='Microsoft.BingNews';                     Impact='No News app' }
    @{ P='Microsoft.Office.Sway';                  Impact='No Sway presentation app' }
    @{ P='Microsoft.Advertising.Xaml*';            Impact='Advertising SDK components removed; some apps that depend on it may break' }
    @{ P='ActiproSoftware*';                       Impact='Code Writer / Actipro apps removed (third-party preinstall)' }
    @{ P='EclipseManager*';                        Impact='Eclipse Manager / Fitbit Coach removed' }
    @{ P='SpotifyAB.SpotifyMusic*';                Impact='Preinstalled Spotify removed (reinstall from Store if needed)' }
    @{ P='king.com.*';                             Impact='Preinstalled Candy Crush games removed' }
    @{ P='Microsoft.549981C3F5F10';                Impact='Cortana (consumer) removed' }
    @{ P='Microsoft.Microsoft3DViewer';             Impact='No 3D Viewer app' }
    @{ P='Microsoft.MSPaint';                      Impact='No legacy Paint 3D app (regular Paint is a separate component and remains)' }
    @{ P='Microsoft.OneNote';                      Impact='No preinstalled OneNote (install from Office/Store if you use it)' }
    @{ P='Microsoft.PowerAutomateDesktop';          Impact='No Power Automate Desktop; lose ability to record UI automations' }
    @{ P='Microsoft.Todos';                        Impact='No Microsoft To Do app' }
    @{ P='Microsoft.MixedReality.Portal';           Impact='No Mixed Reality Portal; cannot use Windows MR headsets' }
    @{ P='Microsoft.ScreenSketch';                 Impact='No Snip & Sketch / Snipping Tool app' }
)

function Set-AppxDebloater {
    param([bool]$DryRun, [array]$AllowList, [switch]$AssumeYes)
    Write-Section "Appx Package Debloater (interactive)"

    if ($AllowList -contains 'KeepAllAppx') {
        Write-Skip "Appx removal skipped (allow-list)."
        return
    }

    # Appx enumeration can throw on heavily-restricted or partially-corrupt
    # Windows installs even with -ErrorAction SilentlyContinue (the cmdlet
    # internally rethrows a COM exception on certain Win11 24H2 builds).
    # Wrap each query so a failure doesn't take down the whole module.
    try {
        $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    } catch {
        Write-Warn "Get-AppxPackage failed: $($_.Exception.Message)"
        $installed = @()
    }
    $candidates = @()
    foreach ($p in $DefaultAppx) {
        $matches = $installed | Where-Object { $_.Name -like $p.P }
        foreach ($m in $matches) {
            $allowMatch = $AllowList | Where-Object { $m.Name -like $_ }
            $candidates += [PSCustomObject]@{
                Name        = $m.Name
                FullName    = $m.PackageFullName
                Provisioned = $false
                AllowListed = [bool]$allowMatch
                Impact      = $p.Impact
            }
        }
    }

    # Provisioned too
    try {
        $prov = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
    } catch {
        Write-Warn "Get-AppxProvisionedPackage failed: $($_.Exception.Message)"
        $prov = @()
    }
    foreach ($p in $DefaultAppx) {
        $matches = $prov | Where-Object { $_.DisplayName -like $p.P }
        foreach ($m in $matches) {
            $candidates += [PSCustomObject]@{
                Name        = $m.DisplayName
                FullName    = $m.PackageName
                Provisioned = $true
                AllowListed = $AllowList -contains $m.DisplayName
                Impact      = $p.Impact
            }
        }
    }

    $candidates = $candidates | Sort-Object -Property Name -Unique
    if (-not $candidates) { Write-Info "No matching Appx packages found."; return }

    # If -AssumeYes: skip interactive entirely, remove everything not allow-listed
    if ($AssumeYes) {
        Write-Info "-AssumeYes set; removing all non-allow-listed packages."
        foreach ($c in ($candidates | Where-Object { -not $_.AllowListed })) {
            $do = if ($c.Provisioned) {
                { Remove-AppxProvisionedPackage -Online -PackageName $c.FullName -ErrorAction Stop }
            } else {
                { Remove-AppxPackage -Package $c.FullName -AllUsers -ErrorAction Stop }
            }
            if ($DryRun) { Write-Info "DRY-RUN: remove $($c.Name)"; Add-Change $Module "appx:$($c.Name)" 'installed' 'preview-removed' 'DRY' }
            else {
                try { & $do; Add-Change $Module "appx:$($c.Name)" 'installed' 'removed' 'OK' }
                catch { Write-Warn "  Failed: $($_.Exception.Message)"; Add-Change $Module "appx:$($c.Name)" 'installed' 'failed' 'ERR' }
            }
        }
        Write-Pass "Appx debloat complete."
        return
    }

    $defaultRemove = 'Y'
    $index = 0
    while ($index -lt $candidates.Count) {
        $c = $candidates[$index]
        $tag = if ($c.Provisioned) { '[PROV]' } else { '[USER]' }
        $al  = if ($c.AllowListed) { '[ALLOW-LISTED]' } else { '' }
        Write-Host ""
        Write-Host ("[{0,2}/{1,-2}] {2}  {3}  {4}" -f ($index+1), $candidates.Count, $c.Name, $tag, $al) -ForegroundColor $(if($c.AllowListed){'DarkGray'}else{'White'})
        # Show impact so the user understands what they lose before answering.
        if ($c.Impact) {
            Write-Host ("     impact: {0}" -f $c.Impact) -ForegroundColor $(if($c.AllowListed){'DarkGray'}else{'Yellow'})
        }

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
                    catch { Write-Warn "  Failed: $($_.Exception.Message)"; Add-Change $Module "appx:$($c.Name)" 'installed' 'failed' 'ERR' }
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

