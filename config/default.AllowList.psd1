# Allow-list: Edit this file (or %ProgramData%\HardenWindows\Config\allowlist.json after first run)
# Items listed here will be EXEMPT from disable/remove.
#
# Structure:
#   Services = @('ServiceName1', 'ServiceName2')
#   Appx     = @('Pattern1', 'Pattern2')   (wildcards ok)
#   Modules  = @{
#       <ModuleName> = @('item', 'item')
#   }

@{
    Services = @(
        # Example: 'wuauserv'  # keep Windows Update even on developer profile
    )

    Appx     = @(
        # Example: 'Microsoft.WindowsCalculator*'
    )

    Modules  = @{
        # smb_network  = @('DisableSMB1')
        # firewall     = @('BlockCalcExe')
    }
}
