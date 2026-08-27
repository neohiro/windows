# office.ps1 -- Macros, ProtectedView, DDE
$Module = 'office'

function Set-OfficeSettings {
    param([bool]$DryRun, [array]$AllowList)
    Write-Section "Microsoft Office hardening"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    $officeKeys = @(
        @{ P='HKCU\Software\Policies\Microsoft\Office\12.0\Publisher\Security'; V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\12.0\Word\Security';       V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\14.0\Publisher\Security'; V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\14.0\Word\Security';       V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\15.0\Outlook\Security';   V='markinternalasunsafe'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\15.0\Word\Security';       V='blockcontentexecutionfrominternet'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\15.0\Excel\Security';      V='blockcontentexecutionfrominternet'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\15.0\PowerPoint\Security'; V='blockcontentexecutionfrominternet'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\15.0\Word\Security';        V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\15.0\Publisher\Security';  V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\16.0\Outlook\Security';    V='markinternalasunsafe'; T='REG_DWORD'; D='0' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\16.0\Word\Security';        V='blockcontentexecutionfrominternet'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\16.0\Excel\Security';       V='blockcontentexecutionfrominternet'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\16.0\PowerPoint\Security'; V='blockcontentexecutionfrominternet'; T='REG_DWORD'; D='1' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\16.0\Word\Security';        V='vbawarnings'; T='REG_DWORD'; D='4' }
        @{ P='HKCU\Software\Policies\Microsoft\Office\16.0\Publisher\Security';  V='vbawarnings'; T='REG_DWORD'; D='4' }
    )
    foreach ($k in $officeKeys) {
        & $do "reg add `"$($k.P)`" /v $($k.V) /t $($k.T) /d $($k.D) /f"
    }

    # DDE disable
    $ddeKeys = @(
        @{ P='HKCU\Software\Microsoft\Office\14.0\Word\Options';         V='DontUpdateLinks'; D='1' }
        @{ P='HKCU\Software\Microsoft\Office\14.0\Word\Options\WordMail';V='DontUpdateLinks'; D='1' }
        @{ P='HKCU\Software\Microsoft\Office\15.0\Word\Options';         V='DontUpdateLinks'; D='1' }
        @{ P='HKCU\Software\Microsoft\Office\15.0\Word\Options\WordMail';V='DontUpdateLinks'; D='1' }
        @{ P='HKCU\Software\Microsoft\Office\16.0\Word\Options';         V='DontUpdateLinks'; D='1' }
        @{ P='HKCU\Software\Microsoft\Office\16.0\Word\Options\WordMail';V='DontUpdateLinks'; D='1' }
    )
    foreach ($k in $ddeKeys) {
        & $do "reg add `"$($k.P)`" /v $($k.V) /t REG_DWORD /d $($k.D) /f"
    }
    Add-Change $Module 'Office:Macros+DDE' 'defaults' 'hardened' $(if($DryRun){'DRY'}else{'OK'})
    Write-Pass "Office hardening applied (only takes effect if Office is installed)."
}

