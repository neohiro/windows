# fileassoc.ps1 -- Hijack ransomware-attractive file associations to Notepad
$Module = 'fileassoc'

$Assocs = @(
    'htafile','wshfile','wsffile','batfile','jsfile','jsefile','vbefile','vbsfile'
)

function Set-FileAssocSettings {
    param([bool]$DryRun, [array]$AllowList, [switch]$AssumeYes)
    Write-Section "File associations (ransomware mitigation)"

    $do = { param($cmd) Invoke-Cmd -Cmd $cmd -DryRun $DryRun }

    if ($AssumeYes) {
        Write-Info "-AssumeYes set; re-associating script extensions to Notepad."
    } else {
        $resp = Invoke-TimedPrompt -Message "Re-associate .bat/.vbs/.js/.hta to Notepad? (skips execution - SAFE for most users, can break power-user workflow)" -Default 'N' -ValidChars @('Y','N','S')
        if ($resp -ne 'Y') {
            Write-Skip "File assoc change skipped by user."
            Add-Change $Module 'FileAssoc' 'unchanged' 'SKIP' 'SKIP'
            return
        }
    }

    foreach ($a in $Assocs) {
        & $do "ftype $a=`"%SystemRoot%\system32\NOTEPAD.EXE`" `"%1`""
        Add-Change $Module "ftype:$a" 'executes' 'notepad' $(if($DryRun){'DRY'}else{'OK'})
    }
    Write-Pass "File associations locked down to Notepad."
}

