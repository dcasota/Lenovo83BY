# ResolveDPAPIWithWMIAndAuditFix.ps1
# PowerShell script to diagnose and resolve DPAPI Unprotect failed errors (Event ID 8198)
# Incorporates WMI activity and process creation auditing with correct German subcategory name
# Implements steps: enable auditing, disable tasks, check software, guide ProcMon, verify master keys, monitor logs
# Tailored for German locale (e.g., "Prozesserstellung", "Detaillierte Nachverfolgung")
# Must be run as Administrator
# Outputs findings to a report file on the Desktop

# Ensure script runs with elevated privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Dieses Skript muss als Administrator ausgeführt werden."
    exit 1
}

# Initialize report file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = "$env:USERPROFILE\DPAPIWMIResolutionReport_$timestamp.txt"
$report = "DPAPI und WMI Auflösungsbericht - Erstellt am $(Get-Date)`n"
$report += "==================================================`n`n"

# Function to append to report
function Add-ToReport {
    param ([string]$Section, [string]$Content)
    $script:report += "$Section`n$Content`n`n"
}

# Function to check DPAPI log
function Check-DPAPILog {
    param ([string]$Context)
    try {
        $events = Get-WinEvent -LogName 'Microsoft-Windows-Crypto-DPAPI/Operational' -MaxEvents 10 |
            Where-Object { $_.Id -eq 8198 } |
            Select-Object TimeCreated, @{Name="Message";Expression={$_.Message}}
        if ($events) {
            $eventDetails = $events | ForEach-Object { "Zeit: $($_.TimeCreated), Nachricht: $($_.Message)" }
            Add-ToReport "DPAPI-Log-Prüfung ($Context)" ($eventDetails -join "`n")
            return $events
        } else {
            Add-ToReport "DPAPI-Log-Prüfung ($Context)" "Keine DPAPI-Fehler in den letzten 10 Ereignissen gefunden."
            return $null
        }
    } catch {
        Add-ToReport "DPAPI-Log-Prüfung ($Context)" "Fehler beim Überprüfen des DPAPI-Logs: $_"
        return $null
    }
}

# Function to check WMI activity around DPAPI error times
function Check-WMIActivity {
    param ([array]$DPAPIEvents)
    try {
        if ($DPAPIEvents) {
            $wmiDetails = foreach ($event in $DPAPIEvents) {
                $time = $event.TimeCreated
                $start = $time.AddSeconds(-30)
                $end = $time.AddSeconds(30)
                Get-WinEvent -LogName 'Microsoft-Windows-WMI-Activity/Operational' -FilterXPath "*[System[TimeCreated[@SystemTime>='$start' and @SystemTime<='$end']]]" -ErrorAction SilentlyContinue |
                    Select-Object TimeCreated, @{Name="PID";Expression={$_.Properties[2].Value}}, @{Name="User";Expression={$_.Properties[1].Value}}, @{Name="Operation";Expression={$_.Properties[5].Value}}
            }
            if ($wmiDetails) {
                $wmiOutput = $wmiDetails | ForEach-Object { "Zeit: $($_.TimeCreated), PID: $($_.PID), Benutzer: $($_.User), Operation: $($_.Operation)" }
                Add-ToReport "WMI-Aktivität nahe DPAPI-Fehlern" ($wmiOutput -join "`n")
            } else {
                Add-ToReport "WMI-Aktivität nahe DPAPI-Fehlern" "Keine WMI-Aktivität nahe DPAPI-Fehlerzeiten gefunden."
            }
        } else {
            Add-ToReport "WMI-Aktivität nahe DPAPI-Fehlern" "Keine DPAPI-Ereignisse für Korrelation mit WMI-Aktivität."
        }
    } catch {
        Add-ToReport "WMI-Aktivität nahe DPAPI-Fehlern" "Fehler beim Überprüfen der WMI-Aktivität: $_"
    }
}

# Function to check process creation events
function Check-ProcessCreation {
    param ([array]$DPAPIEvents)
    try {
        if ($DPAPIEvents) {
            $processDetails = foreach ($event in $DPAPIEvents) {
                $time = $event.TimeCreated
                $start = $time.AddSeconds(-30)
                $end = $time.AddSeconds(30)
                Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4688 and TimeCreated[@SystemTime>='$start' and @SystemTime<='$end']]]" -ErrorAction SilentlyContinue |
                    Select-Object TimeCreated, @{Name="ProcessName";Expression={$_.Properties[5].Value}}, @{Name="PID";Expression={$_.Properties[8].Value}}
            }
            if ($processDetails) {
                $processOutput = $processDetails | ForEach-Object { "Zeit: $($_.TimeCreated), Prozess: $($_.ProcessName), PID: $($_.PID)" }
                Add-ToReport "Prozesserstellungs-Ereignisse nahe DPAPI-Fehlern" ($processOutput -join "`n")
            } else {
                Add-ToReport "Prozesserstellungs-Ereignisse nahe DPAPI-Fehlern" "Keine Prozesserstellungs-Ereignisse nahe DPAPI-Fehlerzeiten gefunden."
            }
        } else {
            Add-ToReport "Prozesserstellungs-Ereignisse nahe DPAPI-Fehlern" "Keine DPAPI-Ereignisse für Korrelation mit Prozesserstellung."
        }
    } catch {
        Add-ToReport "Prozesserstellungs-Ereignisse nahe DPAPI-Fehlern" "Fehler beim Überprüfen der Prozesserstellungs-Ereignisse: $_"
    }
}

# Step 1: Enable Process Creation Auditing
$report += "1. Aktivierung der Prozesserstellungs-Überwachung`n"
try {
    # Check audit policy using category to avoid subcategory name issues
    $auditPolicy = auditpol /get /category:"Detaillierte Nachverfolgung" /r | ConvertFrom-Csv
    $processCreation = $auditPolicy | Where-Object { $_.'Category/Subcategory' -eq 'Prozesserstellung' }
    if ($processCreation -and $processCreation.Setting -notmatch "Erfolg") {
        auditpol /set /subcategory:"Prozesserstellung" /success:enable /failure:enable | Out-Null
        Add-ToReport "Prozesserstellungs-Überwachung" "Prozesserstellungs-Überwachung aktiviert."
    } else {
        Add-ToReport "Prozesserstellungs-Überwachung" "Prozesserstellungs-Überwachung bereits aktiviert oder Status: $($processCreation.Setting)."
    }
    # Force Group Policy update
    gpupdate /force | Out-Null
    Add-ToReport "Gruppenrichtlinienaktualisierung" "Gruppenrichtlinien aktualisiert, um Überwachungsänderungen anzuwenden."
} catch {
    Add-ToReport "Prozesserstellungs-Überwachung" "Fehler beim Aktivieren der Überwachung: $_. Versuchen Sie 'auditpol /set /subcategory:`"Process Creation`" /success:enable /failure:enable' falls 'Prozesserstellung' weiterhin fehlschlägt."
}

# Step 2: Disable High-Priority Scheduled Tasks
$report += "2. Deaktivieren von geplanten Aufgaben mit hoher Priorität`n"
$tasksToDisable = @(
    @{Name="IntelSURQC-Upgrade-86621605-2a0b-4128-8ffc-15514c247132-Logon"; Path="\"; Reason="5-Minuten-Anmeldetrigger, wahrscheinlich Hardwareabfragen (WMI CIMV2, PIDs 19136, 6136)"},
    @{Name="LenovoNowTask"; Path="\Lenovo\"; Reason="Mehrere 5-Minuten-Trigger, Benutzerkontext-WMI-Abfragen (PID 7556)"},
    @{Name="McAfee Windows Notification Token"; Path="\McAfee\WPS\"; Reason="5-Minuten-Anmeldetrigger, potenzieller Zugriff auf Anmeldeinformationen"},
    @{Name="LoginCheck"; Path="\Microsoft\Windows\PushToInstall\"; Reason="5-Minuten-Anmeldetrigger, mögliche RSoP-Aktivität (PID 10824)"},
    @{Name="Work Folders Logon Synchronization"; Path="\Microsoft\Windows\Work Folders\"; Reason="5-Minuten-Anmeldetrigger"}
)

foreach ($task in $tasksToDisable) {
    try {
        $taskInfo = Get-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -ErrorAction SilentlyContinue
        if ($taskInfo -and $taskInfo.State -ne "Disabled") {
            Write-Host "Gefundene aktive Aufgabe: $($task.Name) ($($task.Reason)). Deaktivieren? (j/n)"
            $response = Read-Host
            if ($response -eq 'j') {
                Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path | Out-Null
                Add-ToReport "Aufgabe: $($task.Name)" "Aufgabe bei $($task.Path) deaktiviert. Grund: $($task.Reason)"
                # Wait 6 minutes to check if errors stop
                Write-Host "Warte 6 Minuten, um DPAPI-, WMI- und Prozesserstellungs-Logs nach Deaktivierung von $($task.Name) zu überwachen..."
                Start-Sleep -Seconds 360
                $dpapiEvents = Check-DPAPILog "Nach Deaktivierung von $($task.Name)"
                Check-WMIActivity -DPAPIEvents $dpapiEvents
                Check-ProcessCreation -DPAPIEvents $dpapiEvents
            } else {
                Add-ToReport "Aufgabe: $($task.Name)" "Benutzer hat entschieden, Aufgabe nicht zu deaktivieren. Grund: $($task.Reason)"
            }
        } else {
            Add-ToReport "Aufgabe: $($task.Name)" "Aufgabe nicht gefunden oder bereits deaktiviert. Grund: $($task.Reason)"
        }
    } catch {
        Add-ToReport "Aufgabe: $($task.Name)" "Fehler beim Deaktivieren der Aufgabe: $_"
    }
}

# Step 3: Check Third-Party Software Versions
$report += "3. Überprüfung der Versionen von Drittanbieter-Software`n"
$software = @("Intel*", "McAfee*", "Lenovo*", "CCleaner*")
try {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $software -contains $_.Name -or $_.Name -like $software } |
        Select-Object Name, Version
    if ($installed) {
        $softwareDetails = $installed | ForEach-Object { "Software: $($_.Name), Version: $($_.Version)" }
        Add-ToReport "Installierte Software" ($softwareDetails -join "`n")"`nEmpfehlung: Aktualisieren Sie Intel (über Intel Driver & Support Assistant), McAfee (über McAfee-Update-Tool), Lenovo (über Vantage) und CCleaner (über Website)."
    } else {
        Add-ToReport "Installierte Software" "Keine relevante Drittanbieter-Software gefunden."
    }
} catch {
    Add-ToReport "Installierte Software" "Fehler beim Überprüfen der Software: $_"
}

# Step 4: Guide Process Monitor Setup
$report += "4. Anleitung zur Einrichtung von Process Monitor`n"
$procmonPath = "C:\Program Files\SysinternalsSuite\Procmon.exe"
if (Test-Path $procmonPath) {
    Add-ToReport "Process Monitor" "Process Monitor gefunden unter $procmonPath.`nAnleitung: Führen Sie Procmon.exe als Administrator aus, setzen Sie Filter (Operation=RegQueryValue, Pfad enthält Microsoft\Protect, Ergebnis ist nicht SUCCESS; Operation=IWbemServices, Pfad enthält CIMV2 oder Rsop), erfassen Sie für 10-15 Minuten um DPAPI-Fehlerzeiten (z.B. 21:15:39), und überprüfen Sie Prozessname/PID (z.B. svchost.exe, Lenovo.Vantage.exe)."
} else {
    Add-ToReport "Process Monitor" "Process Monitor nicht gefunden.`nAnleitung: Laden Sie von https://docs.microsoft.com/en-us/sysinternals/downloads/procmon herunter, entpacken Sie, führen Sie Procmon.exe als Administrator aus, setzen Sie Filter (Operation=RegQueryValue, Pfad enthält Microsoft\Protect, Ergebnis ist nicht SUCCESS; Operation=IWbemServices, Pfad enthält CIMV2 oder Rsop), erfassen Sie für 10-15 Minuten um DPAPI-Fehlerzeiten (z.B. 21:15:39), und überprüfen Sie Prozessname/PID (z.B. svchost.exe, Lenovo.Vantage.exe)."
}

# Step 5: Check Master Key Folder
$report += "5. Überprüfung des Master-Schlüssel-Ordners`n"
$protectFolder = "$env:APPDATA\Microsoft\Protect"
try {
    if (Test-Path $protectFolder) {
        $sidFolders = Get-ChildItem $protectFolder -Directory
        if ($sidFolders) {
            $folderDetails = $sidFolders | ForEach-Object {
                $folder = $_.FullName
                $acl = Get-Acl $folder
                $userAccess = $acl.Access | Where-Object { $_.IdentityReference -eq $env:USERNAME } | Select-Object -ExpandProperty FileSystemRights
                $files = Get-ChildItem $folder -File | Measure-Object
                "SID-Ordner: $($_.Name)`nDateien: $($files.Count)`nBenutzerzugriff: $userAccess"
            }
            Add-ToReport "Master-Schlüssel-Ordner" "Ordner existiert unter $protectFolder`n$($folderDetails -join "`n`n")`nEmpfehlung: Stellen Sie sicher, dass der Benutzer Vollzugriff hat. Wenn keine Dateien vorhanden sind, könnten Master-Schlüssel beschädigt sein; erwägen Sie ein Zurücksetzen des Benutzerprofils nach Sicherung."
        } else {
            Add-ToReport "Master-Schlüssel-Ordner" "Ordner existiert, aber keine SID-Unterordner. Mögliche Beschädigung; erwägen Sie ein Zurücksetzen des Benutzerprofils nach Sicherung."
        }
    } else {
        Add-ToReport "Master-Schlüssel-Ordner" "Ordner unter $protectFolder nicht gefunden. DPAPI kann nicht funktionieren; erwägen Sie ein Zurücksetzen des Benutzerprofils nach Sicherung."
    }
} catch {
    Add-ToReport "Master-Schlüssel-Ordner" "Fehler beim Überprüfen des Ordners: $_"
}

# Step 6: Monitor DPAPI, WMI, and Process Creation Logs
$report += "6. Abschließende Überwachung von DPAPI-, WMI- und Prozesserstellungs-Logs`n"
$dpapiEvents = Check-DPAPILog "Abschließende Prüfung"
Check-WMIActivity -DPAPIEvents $dpapiEvents
Check-ProcessCreation -DPAPIEvents $dpapiEvents

# Save report to file
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Bericht gespeichert unter $reportPath"

# Final Recommendations
Write-Host "`nNächste Schritte:"
Write-Host "- Überprüfen Sie den Bericht unter $reportPath."
Write-Host "- Wenn DPAPI-Fehler nach Deaktivierung einer Aufgabe aufhören, ist diese Aufgabe wahrscheinlich die Ursache (z.B. IntelSURQC, LenovoNowTask)."
Write-Host "- Wenn Fehler bestehen, führen Sie Process Monitor wie angewiesen aus, mit Fokus auf WMI (CIMV2, Rsop) und DPAPI (Microsoft\Protect) Aktivität. Teilen Sie Prozessnamen/PIDs mit."
Write-Host "- Aktualisieren Sie Drittanbieter-Software (Intel, McAfee, Lenovo, CCleaner) auf die neuesten Versionen."
Write-Host "- Wenn der Master-Schlüssel-Ordner leer oder nicht zugänglich ist, sichern Sie Daten und wenden Sie sich an den Microsoft-Support für ein Zurücksetzen des Profils."
Write-Host "- Teilen Sie den Bericht, neue DPAPI/WMI-Logs oder ProcMon-Ergebnisse für weitere Analyse."