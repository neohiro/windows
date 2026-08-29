# fileassoc.ps1 -- Hijack ransomware-attractive file associations to Notepad
$Module = 'fileassoc'

$Assocs = @(
    'htafile','wshfile','wsffile','batfile','jsfile','jsefile','vbefile','vbsfile'
)

function Set-FileAssocSettings {
    param([bool]$DryRun, [array]$AllowList, [switch]$AssumeYes, [switch]$ConfirmImpact)
    Write-Section "File associations (ransomware mitigation)"

    # High-impact action: require typed YES even when -AssumeYes is set.
    # Only -ConfirmImpact bypasses the gate. Re-associating .bat/.vbs/.js
    # is irreversible (no snapshot undo) and breaks power-user workflows.
    if (-not $ConfirmImpact) {
        if (-not (Confirm-HighImpact -Action "Re-associate .bat/.vbs/.js/.jse/.hta/.wsf to Notepad" -Impact "Scripts of these types will no longer execute when double-clicked. Power-user workflow break. Cannot be undone by snapshot — only by editing the registry or running the script manually." -DryRun:$DryRun)) {
            Write-Skip "File assoc change skipped (high-impact declined)."
            Add-Change $Module 'FileAssoc' 'unchanged' 'SKIP' 'SKIP'
            return
        }
    } else {
        Write-Info "-ConfirmImpact set; re-associating script extensions to Notepad."
    }

    foreach ($a in $Assocs) {
        Invoke-Cmd -Cmd "ftype $a=`"%SystemRoot%\system32\NOTEPAD.EXE`" `"%1`"" -DryRun $DryRun
        Add-Change $Module "ftype:$a" 'executes' 'notepad' $(if($DryRun){'DRY'}else{'OK'})
    }
    Write-Pass "File associations locked down to Notepad."
}

