# TraceDPAPIProcess.ps1
# PowerShell script to identify the process causing DPAPI Unprotect failed errors (Event ID 8198)
# Must be run as Administrator
# Outputs findings to a report file on the Desktop

# Ensure script runs with elevated privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Initialize report file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = "$env:USERPROFILE\DPAPIProcessTrace_$timestamp.txt"
$report = "DPAPI Process Trace Report - Generated on $(Get-Date)`n"
$report += "==================================================`n`n"

# Function to append to report
function Add-ToReport {
    param ([string]$Section, [string]$Content)
    $script:report += "$Section`n$Content`n`n"
}

# 1. Extract DPAPI Error Events
$report += "1. Recent DPAPI Error Events (Event ID 8198)`n"
try {
    $dpapiEvents = Get-WinEvent -LogName 'Microsoft-Windows-Crypto-DPAPI/Operational' -MaxEvents 10 | 
        Where-Object { $_.Id -eq 8198 } | 
        Select-Object TimeCreated, @{Name="Message";Expression={$_.Message}}
    if ($dpapiEvents) {
        $eventDetails = $dpapiEvents | ForEach-Object { "Time: $($_.TimeCreated), Message: $($_.Message)" }
        Add-ToReport "DPAPI Error Events" ($eventDetails -join "`n")
    } else {
        Add-ToReport "DPAPI Error Events" "No DPAPI error events found."
    }
} catch {
    Add-ToReport "DPAPI Error Events" "Error retrieving DPAPI events: $_"
}

# 2. Check Process Creation Events (Event ID 4688)
$report += "2. Process Creation Events Near DPAPI Errors`n"
try {
    $dpapiTimes = $dpapiEvents | Select-Object -ExpandProperty TimeCreated
    $processEvents = foreach ($time in $dpapiTimes) {
        $start = $time.AddSeconds(-30)
        $end = $time.AddSeconds(30)
        Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4688 and TimeCreated[@SystemTime>='$start' and @SystemTime<='$end']]]" -ErrorAction SilentlyContinue | 
            Select-Object TimeCreated, @{Name="ProcessName";Expression={$_.Properties[5].Value}}, @{Name="PID";Expression={$_.Properties[8].Value}}
    }
    if ($processEvents) {
        $processDetails = $processEvents | ForEach-Object { "Time: $($_.TimeCreated), Process: $($_.ProcessName), PID: $($_.PID)" }
        Add-ToReport "Process Creation Events" ($processDetails -join "`n")
    } else {
        Add-ToReport "Process Creation Events" "No process creation events found near DPAPI errors. Ensure process tracking auditing is enabled."
    }
} catch {
    Add-ToReport "Process Creation Events" "Error retrieving process creation events: $_"
}

# 3. Check Scheduled Tasks (S4U or Frequent Triggers)
$report += "3. Scheduled Tasks (S4U or Frequent Triggers)`n"
try {
    $tasks = Get-ScheduledTask | ForEach-Object {
        $taskName = $_.TaskName
        $taskPath = $_.TaskPath
        try {
            $xml = [xml](Export-ScheduledTask -TaskName $taskName -TaskPath $taskPath)
            $logonType = $xml.GetElementsByTagName("LogonType").'#text'
            $triggers = $xml.Task.Triggers.InnerXml
            [PSCustomObject]@{
                TaskName = $taskName
                TaskPath = $taskPath
                LogonType = $logonType
                Triggers = $triggers
            }
        } catch {
            [PSCustomObject]@{
                TaskName = $taskName
                TaskPath = $taskPath
                LogonType = "Error: $_"
                Triggers = "Error"
            }
        }
    }
    $suspiciousTasks = $tasks | Where-Object { $_.LogonType -eq "S4U" -or $_.Triggers -match "PT[1-5]M" }
    if ($suspiciousTasks) {
        $taskDetails = $suspiciousTasks | ForEach-Object { "Task: $($_.TaskName), Path: $($_.TaskPath), LogonType: $($_.LogonType), Triggers: $($_.Triggers)" }
        Add-ToReport "Scheduled Tasks" ($taskDetails -join "`n")"`nRecommendation: Review and disable tasks with S4U or ~5-minute triggers."
    } else {
        Add-ToReport "Scheduled Tasks" "No suspicious scheduled tasks found (S4U or ~5-minute triggers)."
    }
} catch {
    Add-ToReport "Scheduled Tasks" "Error retrieving scheduled tasks: $_"
}

# Save report to file
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Report saved to $reportPath"

# Final Recommendations
Write-Host "`nNext Steps:"
Write-Host "- Review the report at $reportPath."
Write-Host "- Check Process Creation Events for suspicious processes (e.g., svchost.exe, chrome.exe) around DPAPI error times."
Write-Host "- If svchost.exe is implicated, use Process Monitor to inspect its command line for service details."
Write-Host "- If a scheduled task is listed, disable it in Task Scheduler and monitor for error resolution."
Write-Host "- Run Process Monitor with filters for 'Microsoft\Protect' or 'CryptUnprotectData' to capture live process activity."
Write-Host "- If no clear process is identified, share the report for further analysis."