# Profile presets: control which modules and individual settings are applied.

@{
    Home = @{
        Description = "Privacy + security baseline. Safe for family PCs."
        Modules = @(
            'core','defender','firewall','smb_network','account_lockout',
            'usb_autoplay','powershell_logging','audit_logging',
            'browser','office','privacy','fileassoc','biometrics',
            'powershell_v2','appx_debloater','optional_features','backup_recovery'
        )
        Skip = @('service_debloater')
    }

    Workstation = @{
        Description = "Hardened office workstation. Disables PowerShell remoting, services, and adds strict lockout."
        Modules = @(
            'core','defender','firewall','smb_network','account_lockout',
            'usb_autoplay','powershell_logging','audit_logging',
            'browser','office','privacy','fileassoc','biometrics',
            'powershell_v2','service_debloater','appx_debloater',
            'optional_features','backup_recovery'
        )
        Skip = @()
    }

    Developer = @{
        Description = "Keeps PS remoting, WinRM, Docker, WSL; looser ASR rules."
        Modules = @(
            'core','defender','firewall','smb_network','account_lockout',
            'usb_autoplay','powershell_logging','audit_logging',
            'browser','privacy','biometrics','powershell_v2',
            'appx_debloater','optional_features','backup_recovery'
        )
        Skip = @('fileassoc','office','service_debloater')
    }
}
