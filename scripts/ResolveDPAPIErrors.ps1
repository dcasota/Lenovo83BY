# ResolveDPAPIErrors.ps1
# PowerShell script to diagnose and resolve DPAPI Unprotect failed errors (Event ID 8198)
# Implements steps to enable auditing, disable tasks, check software, guide ProcMon, verify master keys, and monitor logs
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
$reportPath = "$env:USERPROFILE\DPAPIResolutionReport_$timestamp.txt"
$report = "DPAPI Resolution Report - Generated on $(Get-Date)`n"
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
        } else {
            Add-ToReport "DPAPI Log Check ($Context)" "No DPAPI errors found in the last 10 events."
        }
    } catch {
        Add-ToReport "DPAPI Log Check ($Context)" "Error checking DPAPI log: $_"
    }
}

# Step 1: Enable Process Creation Auditing
$report += "1. Enabling Process Creation Auditing`n"
try {
    $auditPolicy = auditpol /get /subcategory:"Process Creation" /r | ConvertFrom-Csv
    if ($auditPolicy.Success -ne "Yes") {
        auditpol /़ /set /subcategory:"Process Creation" /success:enable /failure:enable | Out-Null
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
    @{Name="IntelSURQC-Upgrade-86621605-2a0b-4128-8ffc-15514c247132-Logon"; Path="\"},
    @{Name="McAfee Windows Notification Token"; Path="\McAfee\WPS\"},
    @{Name="LoginCheck"; Path="\Microsoft\Windows\PushToInstall\"},
    @{Name="Work Folders Logon Synchronization"; Path="\Microsoft\Windows\Work Folders\"},
    @{Name="LenovoNowTask"; Path="\Lenovo\"}
)

foreach ($task in $tasksToDisable) {
    try {
        $taskInfo = Get-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -ErrorAction SilentlyContinue
        if ($taskInfo -and $taskInfo.State -ne "Disabled") {
            Write-Host "Found enabled task: $($task.Name). Disable it? (y/n)"
            $response = Read-Host
            if ($response -eq 'y') {
                Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path | Out-Null
                Add-ToReport "Task: $($task.Name)" "Disabled task at $($task.Path)."
                # Wait 6 minutes to check if errors stop
                Write-Host "Waiting 6 minutes to monitor DPAPI log after disabling $($task.Name)..."
                Start-Sleep -Seconds 360
                Check-DPAPILog "After disabling $($task.Name)"
            } else {
                Add-ToReport "Task: $($task.Name)" "User chose not to disable task."
            }
        } else {
            Add-ToReport "Task: $($task.Name)" "Task not found or already disabled."
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
        Add-ToReport "Installed Software" ($softwareDetails -join "`n")"`nRecommendation: Update Intel, McAfee, Lenovo, and CCleaner via their respective tools or websites."
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
    Add-ToReport "Process Monitor" "Process Monitor found at $procmonPath.`nInstructions: Run Procmon.exe as Administrator, set filters (Operation=RegQueryValue, Path contains Microsoft\Protect, Result is not SUCCESS), capture for 10-15 minutes, and check Process Name/PID around error times (e.g., 20:55:39)."
} else {
    Add-ToReport "Process Monitor" "Process Monitor not found.`nInstructions: Download from https://docs.microsoft.com/en-us/sysinternals/downloads/procmon, extract, run Procmon.exe as Administrator, set filters (Operation=RegQueryValue, Path contains Microsoft\Protect, Result is not SUCCESS), capture for 10-15 minutes, and check Process Name/PID around error times (e.g., 20:55:39)."
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
            Add-ToReport "Master Key Folder" "Folder exists at $protectFolder`n$($folderDetails -join "`n`n")`nRecommendation: Ensure user has FullControl. If no files, master keys may be corrupted."
        } else {
            Add-ToReport "Master Key Folder" "Folder exists but no SID subfolders. Possible corruption."
        }
    } else {
        Add-ToReport "Master Key Folder" "Folder not found at $protectFolder. DPAPI cannot function."
    }
} catch {
    Add-ToReport "Master Key Folder" "Error checking folder: $_"
}

# Step 6: Monitor DPAPI Log
$report += "6. Final DPAPI Log Monitoring`n"
Check-DPAPILog "Final Check"

# Save report to file
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Report saved to $reportPath"

# Final Recommendations
Write-Host "`nNext Steps:"
Write-Host "- Review the report at $reportPath."
Write-Host "- If errors stopped after disabling a task, that task is likely the culprit."
Write-Host "- If errors persist, run Process Monitor as instructed and share process names/PIDs."
Write-Host "- Update third-party software (Intel, McAfee, Lenovo, CCleaner) to the latest versions."
Write-Host "- If master key folder is empty or inaccessible, consider resetting the user profile or setting ProtectionPolicy registry key (backup data first)."
Write-Host "- Share the report or new DPAPI log for further analysis if needed."