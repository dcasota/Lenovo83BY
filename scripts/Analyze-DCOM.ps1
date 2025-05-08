# PowerShell script to analyze DCOM permission error in Event Log
# Focus: Investigate CLSID, APPID, user SID, and potential attack indicators

# Define the CLSID, APPID, and SID from the event log
$clsid = "{2593F8B9-4EAF-457C-B68A-50F6B8EA6B54}"
$appid = "{15C20B67-12E7-4BB6-92BB-7AFF07997402}"
$userSid = "S-1-5-21-424017375-788226864-4025993240-1001"
$userAccount = "ltdca\dcaso"

# Output file for logging results
$outputFile = "DCOM_Analysis_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Function to log output to console and file
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $outputFile -Value $logMessage
}

# Initialize the report
Write-Log "Starting DCOM Event Log Analysis for CLSID: $clsid, APPID: $appid, User SID: $userSid"

# Step 1: Resolve CLSID and APPID to identify the COM application
Write-Log "Step 1: Resolving CLSID and APPID in the registry..."

try {
    $clsidPath = "HKLM:\SOFTWARE\Classes\CLSID\$clsid"
    $appidPath = "HKLM:\SOFTWARE\Classes\AppID\$appid"

    # Get CLSID details
    if (Test-Path $clsidPath) {
        $clsidDetails = Get-ItemProperty -Path $clsidPath
        $appName = $clsidDetails.'(default)'
        $localServer = $clsidDetails.LocalServer32
        Write-Log "CLSID Found: $appName"
        if ($localServer) {
            Write-Log "Associated Executable: $localServer"
        }
    } else {
        Write-Log "CLSID $clsid not found in registry."
    }

    # Get APPID details
    if (Test-Path $appidPath) {
        $appidDetails = Get-ItemProperty -Path $appidPath
        $appIdName = $appidDetails.'(default)'
        $serviceName = $appidDetails.ServiceName
        Write-Log "APPID Found: $appIdName"
        if ($serviceName) {
            Write-Log "Associated Service: $serviceName"
        }
    } else {
        Write-Log "APPID $appid not found in registry."
    }
} catch {
    Write-Log "Error accessing registry for CLSID/APPID: $_"
}

# Step 2: Resolve the user SID to a username
Write-Log "Step 2: Resolving User SID: $userSid..."

try {
    $sidObject = New-Object System.Security.Principal.SecurityIdentifier($userSid)
    $userName = $sidObject.Translate([System.Security.Principal.NTAccount]).Value
    Write-Log "SID $userSid resolves to: $userName"
} catch {
    Write-Log "Error resolving SID $userSid. Likely a deleted or non-existent account: $_"
}

# Step 3: Check DCOM permissions for the CLSID/APPID
Write-Log "Step 3: Checking DCOM permissions for APPID: $appid..."

try {
    $dcomConfig = Get-WmiObject -Query "SELECT * FROM Win32_DCOMApplicationSetting WHERE AppID = '$appid'"
    if ($dcomConfig) {
        Write-Log "DCOM Application Found: $($dcomConfig.Caption)"
        Write-Log "Launch and Activation Permissions: $($dcomConfig.LaunchSecurityDescriptor)"
        Write-Log "Access Permissions: $($dcomConfig.AccessSecurityDescriptor)"
    } else {
        Write-Log "No DCOM configuration found for APPID: $appid"
    }
} catch {
    Write-Log "Error querying DCOM configuration: $_"
}

# Step 4: Check Event Logs for related DCOM or security events
Write-Log "Step 4: Checking Event Logs for related DCOM or security events..."

try {
    # Search System Event Log for DCOM errors (Event ID 10016)
    $dcomEvents = Get-WinEvent -LogName "System" -MaxEvents 1000 | Where-Object {
        $_.Id -eq 10016 -and $_.Message -match $clsid
    }
    if ($dcomEvents) {
        Write-Log "Found $($dcomEvents.Count) DCOM-related events (Event ID 10016) for CLSID: $clsid"
        foreach ($event in $dcomEvents) {
            Write-Log "Event Time: $($event.TimeCreated), Message: $($event.Message)"
        }
    } else {
        Write-Log "No additional DCOM events found for CLSID: $clsid"
    }

    # Search Security Event Log for related audit failures
    $securityEvents = Get-WinEvent -LogName "Security" -MaxEvents 1000 | Where-Object {
        $_.Id -eq 4672 -or $_.Id -eq 4673 -and $_.Message -match $userSid
    }
    if ($securityEvents) {
        Write-Log "Found $($securityEvents.Count) security events related to SID: $userSid"
        foreach ($event in $securityEvents) {
            Write-Log "Event Time: $($event.TimeCreated), Event ID: $($event.Id), Message: $($event.Message)"
        }
    } else {
        Write-Log "No security events found for SID: $userSid"
    }
} catch {
    Write-Log "Error querying Event Logs: $_"
}

# Step 5: Investigate potential attack indicators
Write-Log "Step 5: Investigating potential DCOM attack indicators..."

# Check running processes related to the application
if ($localServer) {
    $exeName = [System.IO.Path]::GetFileName($localServer)
    Write-Log "Checking for running processes related to: $exeName"
    $processes = Get-Process -Name $exeName -ErrorAction SilentlyContinue
    if ($processes) {
        foreach ($proc in $processes) {
            Write-Log "Found process: $($proc.Name) (PID: $($proc.Id), Path: $($proc.Path))"
            # Check process owner
            $owner = (Get-WmiObject Win32_Process -Filter "ProcessId = $($proc.Id)").GetOwner()
            Write-Log "Process Owner: $($owner.Domain)\$($owner.User)"
        }
    } else {
        Write-Log "No running processes found for: $exeName"
    }
}

# Check network connections for suspicious activity
Write-Log "Checking network connections for suspicious activity..."
$netConnections = Get-NetTCPConnection | Where-Object { $_.OwningProcess -in $processes.Id }
if ($netConnections) {
    foreach ($conn in $netConnections) {
        Write-Log "Suspicious connection: Local: $($conn.LocalAddress):$($conn.LocalPort), Remote: $($conn.RemoteAddress):$($conn.RemotePort), State: $($conn.State)"
    }
} else {
    Write-Log "No suspicious network connections found."
}

# Step 6: Recommendations
Write-Log "Step 6: Recommendations"
Write-Log "- Verify if the application ($appName) is legitimate and expected to run."
Write-Log "- Check DCOM permissions using 'dcomcnfg' (Component Services) for APPID: $appid."
Write-Log "- Ensure the user ($userName) should have 'Local Activation' permissions."
Write-Log "- Monitor Event Logs for repeated DCOM errors or security audit failures."
Write-Log "- If suspicious, scan the system with an updated antivirus and investigate $localServer for tampering."
Write-Log "- Consider restricting DCOM access if not required (via Group Policy or registry)."

# Finalize the report
Write-Log "Analysis complete. Report saved to: $outputFile"