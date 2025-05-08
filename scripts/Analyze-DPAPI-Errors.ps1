# Analyze-DPAPI-Errors.ps1
# PowerShell script to analyze DPAPI errors in Microsoft-Windows-Crypto-DPAPI/Operational event log
# and provide optional fixes for Windows 11 Professional

# Requires elevated privileges
#Requires -RunAsAdministrator

# Function to generate a unique log file name with timestamp
function Get-LogFileName {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    return "DPAPI_Error_Analysis_$timestamp.txt"
}

# Initialize log file
$logFile = Join-Path -Path $env:TEMP -ChildPath (Get-LogFileName)
"DPAPI Error Analysis Report" | Out-File -FilePath $logFile -Encoding UTF8
"Generated on: $(Get-Date)" | Out-File -FilePath $logFile -Append
"OS: $([System.Environment]::OSVersion.VersionString)" | Out-File -FilePath $logFile -Append
"User: $env:USERNAME" | Out-File -FilePath $logFile -Append
"" | Out-File -FilePath $logFile -Append

# Function to write to both console and log file
function Write-Log {
    param($Message)
    Write-Host $Message
    $Message | Out-File -FilePath $logFile -Append
}

# Function to prompt user for confirmation
function Confirm-Action {
    param($Prompt)
    $response = Read-Host "$Prompt (y/n)"
    return $response -eq 'y' -or $response -eq 'Y'
}

# Step 1: Retrieve DPAPI error events from the last 24 hours
Write-Log "Step 1: Retrieving DPAPI error events from Microsoft-Windows-Crypto-DPAPI/Operational"
$startTime = (Get-Date).AddHours(-24)
$events = Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-Crypto-DPAPI/Operational'
    StartTime = $startTime
    Level = 2,3  # Error and Warning
} -ErrorAction SilentlyContinue | Where-Object {
    $_.Id -eq 8196 -or $_.Id -eq 8198  # Master Key decryption failed (8196), DPAPI Unprotect failed (8198)
}

if (-not $events) {
    Write-Log "No DPAPI error events (IDs 8196, 8198) found in the last 24 hours."
} else {
    Write-Log "Found $($events.Count) DPAPI error events."
    $eventSummary = $events | Group-Object -Property Id | ForEach-Object {
        "Event ID $($_.Name): $($_.Count) occurrences"
    }
    Write-Log ($eventSummary -join "`n")
    
    # Save event details for analysis
    $eventDetails = $events | Select-Object TimeCreated, Id, Message | Format-Table -AutoSize | Out-String
    Write-Log "Event Details:`n$eventDetails"
}

# Step 2: Check for S4U scheduled tasks (common cause of DPAPI issues)
Write-Log "Step 2: Checking for S4U scheduled tasks that may interfere with DPAPI"
$tasks = Get-ScheduledTask | Where-Object {
    $_.Principal.LogonType -eq 'S4U'
}

if ($tasks) {
    Write-Log "Found $($tasks.Count) S4U scheduled tasks that may cause DPAPI issues:"
    $taskDetails = $tasks | Select-Object TaskName, TaskPath, @{Name='Principal';Expression={$_.Principal.UserId}} | Format-Table -AutoSize | Out-String
    Write-Log $taskDetails
    Write-Log "Recommendation: Disabling unnecessary S4U tasks can prevent DPAPI failures, as they may delete credentials in LSASS."
    
    foreach ($task in $tasks) {
        $taskName = $task.TaskName
        if (Confirm-Action "Would you like to disable the scheduled task '$taskName'?") {
            try {
                Disable-ScheduledTask -TaskName $taskName -TaskPath $task.TaskPath -ErrorAction Stop
                Write-Log "Successfully disabled task: $taskName"
            } catch {
                Write-Log "ERROR: Failed to disable task '$taskName'. Exception: $($_.Exception.Message)"
            }
        } else {
            Write-Log "User chose not to disable task: $taskName"
        }
    }
} else {
    Write-Log "No S4U scheduled tasks found."
}

# Step 3: Check domain connectivity for RWDC availability (if domain-joined)
Write-Log "Step 3: Checking domain connectivity for RWDC availability"
$domainInfo = Get-WmiObject -Class Win32_ComputerSystem
if ($domainInfo.PartOfDomain) {
    Write-Log "System is domain-joined: $($domainInfo.Domain)"
    try {
        $rwdc = nltest /dsgetdc:$($domainInfo.Domain) /writeable
        if ($rwdc) {
            Write-Log "RWDC found: $($rwdc)"
        } else {
            Write-Log "ERROR: No writable domain controller (RWDC) found."
            Write-Log "Root Cause: DPAPI Master Key backup may fail if no RWDC is available, causing errors (0x80090345)."
            Write-Log "Fix: Ensure network connectivity to an RWDC or set registry key to allow local backup."
        }
    } catch {
        Write-Log "ERROR: Failed to query RWDC. Exception: $($_.Exception.Message)"
    }
} else {
    Write-Log "System is not domain-joined. RWDC check not applicable."
}

# Step 4: Check and optionally set ProtectionPolicy registry key
Write-Log "Step 4: Checking DPAPI ProtectionPolicy registry key"
$regPath = "HKLM:\SOFTWARE\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb"
$regValue = Get-ItemProperty -Path $regPath -Name ProtectionPolicy -ErrorAction SilentlyContinue
if ($regValue -and $regValue.ProtectionPolicy -eq 1) {
    Write-Log "ProtectionPolicy is set to 1 (local backup enabled)."
} else {
    Write-Log "ProtectionPolicy is not set or not equal to 1."
    Write-Log "Recommendation: Setting ProtectionPolicy to 1 enables local Master Key backup, useful for non-domain systems or if RWDC is unavailable."
    
    if (Confirm-Action "Would you like to set ProtectionPolicy to 1 (DWORD) in the registry?") {
        try {
            New-Item -Path $regPath -Force -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $regPath -Name ProtectionPolicy -Value 1 -Type DWord -ErrorAction Stop
            Write-Log "Successfully set ProtectionPolicy to 1."
        } catch {
            Write-Log "ERROR: Failed to set ProtectionPolicy registry key. Exception: $($_.Exception.Message)"
        }
    } else {
        Write-Log "User chose not to set ProtectionPolicy registry key."
    }
}

# Step 5: Test Credential Manager functionality
Write-Log "Step 5: Testing Credential Manager functionality"
try {
    $credManTest = cmdkey /list
    if ($credManTest) {
        Write-Log "Credential Manager access successful."
    } else {
        Write-Log "WARNING: Credential Manager returned no credentials, but access was successful."
    }
} catch {
    Write-Log "ERROR: Credential Manager access failed. Exception: $($_.Exception.Message)"
    Write-Log "Root Cause: DPAPI issues may prevent Credential Manager from functioning, leading to repeated authentication prompts."
    Write-Log "Fix: Verify RWDC connectivity or set ProtectionPolicy registry key."
}

# Step 6: Generate diagnostic recommendations
Write-Log "Step 6: Summary and Recommendations"
Write-Log "Based on the analysis, consider the following actions (applied fixes are logged above):"
if ($tasks) {
    Write-Log "- Review and disable S4U scheduled tasks that may interfere with DPAPI (prompted above)."
}
if ($domainInfo.PartOfDomain -and -not $rwdc) {
    Write-Log "- Ensure connectivity to a writable domain controller (RWDC) for Master Key backup."
    Write-Log "- Alternatively, set ProtectionPolicy registry key to 1 for local backup (prompted above, not recommended for roaming users)."
}
if (-not $regValue -or $regValue.ProtectionPolicy -ne 1) {
    Write-Log "- Set HKLM\SOFTWARE\Microsoft\Cryptography\Protect\Providers\df9d8cd0-1501-11d1-8c7a-00c04fc297eb\ProtectionPolicy to 1 (DWORD) to enable local backup (prompted above)."
}
Write-Log "- Monitor event logs after applying fixes to confirm resolution."
Write-Log "- If issues persist, collect NETLOGON.LOG and network traces for further analysis (see Microsoft documentation: https://docs.microsoft.com/en-us/troubleshoot/windows-server/identity/dpapi-masterkey-backup-failures)."
Write-Log "- Check for Windows updates, as DPAPI bugs may be addressed in newer patches."

# Step 7: Finalize report
Write-Log ""
Write-Log "Analysis complete. Report saved to: $logFile"
Write-Log "Please review the applied fixes and recommendations."

# Open the log file
Invoke-Item $logFile