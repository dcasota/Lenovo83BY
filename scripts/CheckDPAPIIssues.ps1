# CheckDPAPIIssues.ps1
# PowerShell script to diagnose DPAPI Unprotect failed errors (Event ID 8198) on a standalone Windows 11 Professional system
# Must be run as Administrator
# Outputs findings to a report file in the user's Desktop directory

# Ensure script runs with elevated privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator. Please restart PowerShell with elevated privileges."
    exit 1
}

# Initialize report file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = "$env:USERPROFILE\DPAPIDiagnosticReport_$timestamp.txt"
$report = "DPAPI Diagnostic Report - Generated on $(Get-Date)`n"
$report += "==================================================`n`n"

# Function to append to report
function Add-ToReport {
    param ([string]$Section, [string]$Content)
    $script:report += "$Section`n$Content`n`n"
}

# 1. Check for Scheduled Tasks with S4U Logon Type
$report += "1. Checking for Scheduled Tasks with S4U Logon Type`n"
try {
    $s4uTasks = Get-ScheduledTask | ForEach-Object {
        $taskName = $_.TaskName
        $taskPath = $_.TaskPath
        try {
            $xml = [xml](Export-ScheduledTask -TaskName $taskName -TaskPath $taskPath)
            if ($xml.GetElementsByTagName("LogonType").'#text' -eq "S4U") {
                "$taskName (Path: $taskPath)"
            }
        } catch {
            "Error inspecting task $taskName : $_"
        }
    }
    if ($s4uTasks) {
        Add-ToReport "Scheduled Tasks with S4U Logon Type" "Found S4U tasks that may cause DPAPI issues:`n$($s4uTasks -join "`n")`nRecommendation: Review and disable these tasks in Task Scheduler if associated with apps like HP or Carbonite."
    } else {
        Add-ToReport "Scheduled Tasks with S4U Logon Type" "No S4U tasks found."
    }
} catch {
    Add-ToReport "Scheduled Tasks with S4U Logon Type" "Error checking scheduled tasks: $_"
}

# 2. Verify Master Key Files
$report += "2. Checking DPAPI Master Key Files`n"
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
            Add-ToReport "Master Key Files" "Master key folder exists at $protectFolder`n$($folderDetails -join "`n`n")`nRecommendation: Ensure user has FullControl permissions. If no files exist, master keys may be corrupted."
        } else {
            Add-ToReport "Master Key Files" "Master key folder exists but contains no SID subfolders. Possible corruption or misconfiguration."
        }
    } else {
        Add-ToReport "Master Key Files" "Master key folder not found at $protectFolder. DPAPI cannot function without this folder."
    }
} catch {
    Add-ToReport "Master Key Files" "Error checking master key files: $_"
}

# 3. Determine Account Type
$report += "3. Checking User Account Type`n"
try {
    $user = Get-WmiObject -Class Win32_UserAccount -Filter "Name='$env:USERNAME'"
    $isLocal = $user.LocalAccount
    $accountType = if ($isLocal) { "Local Account" } else { "Microsoft Account or Domain Account" }
    $syncStatus = if ($isLocal) {
        $syncSetting = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SettingSync" -Name "SyncPolicy" -ErrorAction SilentlyContinue
        if ($syncSetting) { "Sync enabled" } else { "Sync disabled or not configured" }
    } else { "Not applicable for non-local accounts" }
    Add-ToReport "User Account Type" "Account: $env:USERNAME`nType: $accountType`nSync Status: $syncStatus`nRecommendation: If using a local account with sync enabled, try switching to a Microsoft account to resolve potential credential issues."
} catch {
    Add-ToReport "User Account Type" "Error checking account type: $_"
}

# 4. Review Recent Windows Updates
$report += "4. Checking Recent Windows Updates`n"
try {
    $updates = Get-WmiObject -Class Win32_QuickFixEngineering | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 5
    if ($updates) {
        $updateDetails = $updates | ForEach-Object { "KB: $($_.HotFixID), Installed: $($_.InstalledOn)" }
        Add-ToReport "Recent Windows Updates" "Last 5 updates:`n$($updateDetails -join "`n")`nRecommendation: Check if errors started after a specific update. Consider rolling back recent updates."
    } else {
        Add-ToReport "Recent Windows Updates" "No recent updates found."
    }
} catch {
    Add-ToReport "Recent Windows Updates" "Error checking updates: $_"
}

# 5. Check Application Errors in Event Log
$report += "5. Checking Application Errors in Event Log`n"
try {
    $appErrors = Get-WinEvent -LogName Application -MaxEvents 100 -ErrorAction SilentlyContinue | Where-Object {
        $_.LevelDisplayName -eq "Error" -and $_.TimeCreated -ge (Get-Date).AddHours(-24)
    } | Select-Object TimeCreated, ProviderName, Id, Message
    if ($appErrors) {
        $errorDetails = $appErrors | ForEach-Object { "Time: $($_.TimeCreated), Source: $($_.ProviderName), ID: $($_.Id), Message: $($_.Message)" }
        Add-ToReport "Application Errors" "Recent application errors (last 24 hours):`n$($errorDetails -join "`n")`nRecommendation: Look for errors from apps like Chrome, Edge, or Quicken that might correlate with DPAPI failures."
    } else {
        Add-ToReport "Application Errors" "No application errors found in the last 24 hours."
    }
} catch {
    Add-ToReport "Application Errors" "Error checking application event log: $_"
}

# Save report to file
$report | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "Diagnostic report saved to $reportPath"

# Final Recommendations
Write-Host "`nSummary of Findings and Next Steps:"
Write-Host "- Review the report at $reportPath for detailed findings."
Write-Host "- If S4U tasks are found, disable them in Task Scheduler and monitor for error resolution."
Write-Host "- If master key folder issues are detected, verify permissions or consider resetting the user profile."
Write-Host "- If using a local account with sync enabled, try switching to a Microsoft account."
Write-Host "- If errors correlate with a recent update, consider rolling it back via Settings > Windows Update > Update History."
Write-Host "- Check for application errors from browsers or apps like Quicken, and update or reinstall them if needed."
Write-Host "`nFor further assistance, share the report content or additional system details."