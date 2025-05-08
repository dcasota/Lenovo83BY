# ResolveDPAPIWithWMI.ps1
# PowerShell script to diagnose and resolve DPAPI Unprotect failed errors (Event ID 8198)
# Incorporates WMI activity analysis to trace processes causing errors
# Implements steps: enable auditing, disable tasks, check software, guide ProcMon, verify master keys, monitor logs
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
$reportPath = "$env:USERPROFILE\Desktop\DPAPIWMIResolutionReport_$timestamp.txt"
$report = "DPAPI and WMI Resolution Report - Generated on $(Get-Date)`n"
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
            $eventDetails = $events | ForEach-Object { "Time: $($_.TimeCreated), Message: $($_.Message)" }
            Add-ToReport "DPAPI Log Check ($Context)" ($eventDetails -join "`n")
            return $events
        } else {
            Add-ToReport "DPAPI Log Check ($Context)" "No DPAPI errors found in the last 10 events."
            return $null
        }
    } catch {
        Add-ToReport "DPAPI Log Check ($Context)" "Error checking DPAPI log: $_"
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
                $wmiOutput = $wmiDetails | ForEach-Object { "Time: $($_.TimeCreated), PID: $($_.PID), User: $($_.User), Operation: $($_.Operation)" }
                Add-ToReport "WMI Activity Near DPAPI Errors" ($wmiOutput -join "`n")
            } else {
                Add-ToReport "WMI Activity Near DPAPI Errors" "No WMI activity found near DPAPI error times."
            }
        } else {
            Add-ToReport "WMI Activity Near DPAPI Errors" "No DPAPI events to correlate with WMI activity."
        }
    } catch {
        Add-ToReport "WMI Activity Near DPAPI Errors" "Error checking WMI activity: $_"
    }
}

# Step 1: Enable Process Creation Auditing
$report += "1. Enabling Process Creation Auditing`n"
try {
    $auditPolicy = auditpol /get /subcategory:"Process Creation" /r | ConvertFrom-Csv
    if ($auditPolicy.Success -ne "Yes") {
        auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable | Out-Null
        Add-ToReport "Process Creation Auditing" "Process creation auditing enabled."
    } else {
        Add-ToReport "Process Creation Auditing" "Process creation auditing already enabled."
    }
    # Force Group Policy update
    gpupdate /force | Out-Null
    Add-ToReport "Group Policy Update" "Group policy updated to apply auditing changes."
} catch {
    Add-ToReport "Process Creation Auditing" "Error enabling auditing: $_"
}

# Step 2: Disable High-Priority Scheduled Tasks
$report += "2. Disabling High-Priority Scheduled Tasks`n"
$tasksToDisable = @(
    @{Name="IntelSURQC-Upgrade-86621605-2a0b-4128-8ffc-15514c247132-Logon"; Path="\"; Reason="5-minute logon trigger, likely hardware queries (WMI CIMV2)"},
    @{Name="LenovoNowTask"; Path="\Lenovo\"; Reason="Multiple 5-minute triggers, user-context WMI queries"},
    @{Name="McAfee Windows Notification Token"; Path="\McAfee\WPS\"; Reason="5-minute logon trigger, potential credential access"},
    @{Name="LoginCheck"; Path="\Microsoft\Windows\PushToInstall\"; Reason="5-minute logon trigger, possible RSoP activity"},
    @{Name="Work Folders Logon Synchronization"; Path="\Microsoft\Windows\Work Folders\"; Reason="5-minute logon trigger"}
)

foreach ($task in $tasksToDisable) {
    try {
        $taskInfo = Get-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -ErrorAction SilentlyContinue
        if ($taskInfo -and $taskInfo.State -ne "Disabled") {
            Write-Host "Found enabled task: $($task.Name) ($($task.Reason)). Disable it? (y/n)"
            $response = Read-Host
            if ($response -eq 'y') {
                Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path | Out-Null
                Add-ToReport "Task: $($task.Name)" "Disabled task at $($task.Path). Reason: $($task.Reason)"
                # Wait 6 minutes to check if errors stop
                Write-Host "Waiting 6 minutes to monitor DPAPI and WMI logs after disabling $($task.Name)..."
                Start-Sleep -Seconds 360
                $dpapiEvents = Check-DPAPILog "After disabling $($task.Name)"
                Check-WMIActivity -DPAPIEvents $dpapiEvents
            } else {
                Add-ToReport "Task: $($task.Name)" "User chose not to disable task. Reason: $($task.Reason)"
            }
        } else {
            Add-ToReport "Task: $($task.Name)" "Task not found or already disabled. Reason: $($task.Reason)"
        }
    } catch {
        Add-ToReport "Task: $($task.Name)" "Error disabling task: $_"
    }
}

# Step 3: Check Third-Party Software Versions
$report += "3. Checking Third-Party Software Versions`n"
$software = @("Intel*", "McAfee*", "Lenovo*", "CCleaner*")
try {
    $installed = Get-WmiObject -Class Win32_Product | Where-Object { $software -contains $_.Name -or $_.Name -like $software } |
        Select-Object Name, Version
    if ($installed) {
        $softwareDetails = $installed | ForEach-Object { "Software: $($_.Name), Version: $($_.Version)" }
        Add-ToReport "Installed Software" ($softwareDetails -join "`n")"`nRecommendation: Update Intel (via Intel Driver & Support Assistant), McAfee (via McAfee update tool), Lenovo (via Vantage), and CCleaner (via website)."
    } else {
        Add-ToReport "Installed Software" "No relevant third-party software found."
    }
} catch {
    Add-ToReport "Installed Software" "Error checking software: $_"
}

# Step 4: Guide Process Monitor Setup
$report += "4. Process Monitor Setup Instructions`n"
$procmonPath = "C:\Program Files\SysinternalsSuite\Procmon.exe"
if (Test-Path $procmonPath) {
    Add-ToReport "Process Monitor" "Process Monitor found at $procmonPath.`nInstructions: Run Procmon.exe as Administrator, set filters (Operation=RegQueryValue, Path contains Microsoft\Protect, Result is not SUCCESS; Operation=IWbemServices, Path contains CIMV2 or Rsop), capture for 10-15 minutes around DPAPI error times (e.g., 21:15:39), and check Process Name/PID (e.g., svchost.exe, Lenovo.Vantage.exe)."
} else {
    Add-ToReport "Process Monitor" "Process Monitor not found.`nInstructions: Download from https://docs.microsoft.com/en-us/sysinternals/downloads/procmon, extract, run Procmon.exe as Administrator, set filters (Operation=RegQueryValue, Path contains Microsoft\Protect, Result is not SUCCESS; Operation=IWbemServices, Path contains CIMV2 or Rsop), capture for 10-15 minutes around DPAPI error times (e.g., 21:15:39), and check Process Name/PID (e.g., svchost.exe, Lenovo.Vantage.exe)."
}

# Step 5: Check Master Key Folder
$report += "5. Checking Master Key Folder`n"
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
                "SID Folder: $($_.Name)`nFiles: $($files.Count)`nUser Access: $userAccess"
            }
            Add-ToReport "Master Key Folder" "Folder exists at $protectFolder`n$($folderDetails -join "`n`n")`nRecommendation: Ensure user has FullControl. If no files, master keys may be corrupted; consider resetting user profile after backup."
        } else {
            Add-ToReport "Master Key Folder" "Folder exists but no SID subfolders. Possible corruption; consider resetting user profile after backup."
        }
    } else {
        Add-ToReport "Master Key Folder" "Folder not found at $protectFolder. DPAPI cannot function; consider resetting user profile after backup."
    }
} catch {
    Add-ToReport "Master Key Folder" "Error checking folder: $_"
}

# Step 6: Monitor DPAPI and WMI Logs
$report += "6. Final DPAPI and WMI Log Monitoring`n"
$dpapiEvents = Check-DPAPILog "Final Check"
Check-WMIActivity -DPAPIEvents $dpapiEvents

# Save report to file
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Report saved to $reportPath"

# Final Recommendations
Write-Host "`nNext Steps:"
Write-Host "- Review the report at $reportPath."
Write-Host "- If DPAPI errors stopped after disabling a task, that task is likely the culprit (e.g., IntelSURQC, LenovoNowTask)."
Write-Host "- If errors persist, run Process Monitor as instructed, focusing on WMI (CIMV2, Rsop) and DPAPI (Microsoft\Protect) activity. Share process names/PIDs."
Write-Host "- Update third-party software (Intel, McAfee, Lenovo, CCleaner) to the latest versions."
Write-Host "- If master key folder is empty or inaccessible, back up data and consult Microsoft support for profile reset."
Write-Host "- Share the report, new DPAPI/WMI logs, or ProcMon results for further analysis."