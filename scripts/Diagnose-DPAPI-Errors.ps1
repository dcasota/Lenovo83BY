#Requires -RunAsAdministrator

# Script to diagnose DPAPI Master Key decryption and Unprotect failures
# Assumes Process Monitor is located at C:\Users\dcaso\Downloads\ProcessMonitor\procmon.exe

# Define paths and variables
$ProcMonPath = "C:\Users\dcaso\Downloads\ProcessMonitor\procmon.exe"
$OutputDir = "C:\Users\dcaso\Downloads\DPAPI_Diagnosis"
$ProcMonLog = "$OutputDir\ProcMon_Log.pml"
$EventLogCsv = "$OutputDir\DPAPI_Events.csv"
$SummaryReport = "$OutputDir\DPAPI_Diagnosis_Summary.txt"
$DiagnosticFilePath = "C:\ProgramData\Microsoft\Crypto\DPAPI\Diagnostic"  # Common location for DPAPI diagnostic logs

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force
}

# Function to log messages to console and summary file
function Write-Log {
    param($Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Host $LogMessage
    Add-Content -Path $SummaryReport -Value $LogMessage
}

# Initialize summary report
Write-Log "Starting DPAPI Error Diagnosis"

# Step 1: Retrieve DPAPI-related events from Event Log
Write-Log "Retrieving DPAPI events from Microsoft-Windows-Crypto-DPAPI/Operational log"
$Events = Get-WinEvent -LogName "Microsoft-Windows-Crypto-DPAPI/Operational" -MaxEvents 1000 -ErrorAction SilentlyContinue |
    Where-Object { $_.LevelDisplayName -eq "Error" -and ($_.Message -like "*Master Key decryption failed*" -or $_.Message -like "*DPAPI Unprotect failed*") } |
    Select-Object TimeCreated, Id, Message, @{Name="ProcessId";Expression={$_.Properties[0].Value}}, @{Name="ThreadId";Expression={$_.Properties[1].Value}}

# Export events to CSV for analysis
if ($Events) {
    $Events | Export-Csv -Path $EventLogCsv -NoTypeInformation
    Write-Log "Exported $($Events.Count) DPAPI error events to $EventLogCsv"
} else {
    Write-Log "No DPAPI error events found in the last 1000 events"
}

# Step 2: Check if Process Monitor exists and is executable
if (-not (Test-Path $ProcMonPath)) {
    Write-Log "ERROR: Process Monitor not found at $ProcMonPath"
    exit
}

# Step 3: Run Process Monitor to capture activity for 5 minutes (error interval)
Write-Log "Starting Process Monitor to capture activity for 5 minutes"
$ProcMonConfig = "/Quiet /Minimized /BackingFile $ProcMonLog /AcceptEula"
Start-Process -FilePath $ProcMonPath -ArgumentList $ProcMonConfig -NoNewWindow

# Wait for 5 minutes to capture events
Write-Log "Waiting for 5 minutes to capture process activity..."
Start-Sleep -Seconds 300

# Terminate Process Monitor
Write-Log "Stopping Process Monitor"
Start-Process -FilePath $ProcMonPath -ArgumentList "/Terminate" -NoNewWindow
Start-Sleep -Seconds 5  # Allow time for ProcMon to save the log

# Step 4: Analyze Process Monitor log (requires manual analysis or ProcMon CLI if available)
if (Test-Path $ProcMonLog) {
    Write-Log "Process Monitor log saved to $ProcMonLog"
    Write-Log "Please analyze $ProcMonLog using Process Monitor GUI to identify processes accessing DPAPI around $($Events[0].TimeCreated)"
} else {
    Write-Log "ERROR: Process Monitor log was not created"
}

# Step 5: Check Cryptographic Services
Write-Log "Checking status of Cryptographic Services"
$CryptoService = Get-Service -Name "CryptSvc"
if ($CryptoService.Status -eq "Running") {
    Write-Log "Cryptographic Services is running"
} else {
    Write-Log "WARNING: Cryptographic Services is not running. Attempting to start..."
    Start-Service -Name "CryptSvc" -ErrorAction SilentlyContinue
    if ((Get-Service -Name "CryptSvc").Status -eq "Running") {
        Write-Log "Cryptographic Services started successfully"
    } else {
        Write-Log "ERROR: Failed to start Cryptographic Services"
    }
}

# Step 6: Check for diagnostic file
Write-Log "Checking for DPAPI diagnostic files in $DiagnosticFilePath"
if (Test-Path $DiagnosticFilePath) {
    $DiagnosticFiles = Get-ChildItem -Path $DiagnosticFilePath -ErrorAction SilentlyContinue
    if ($DiagnosticFiles) {
        Write-Log "Found $($DiagnosticFiles.Count) diagnostic files. Please review these files for master key details."
    } else {
        Write-Log "No diagnostic files found in $DiagnosticFilePath"
    }
} else {
    Write-Log "Diagnostic file path $DiagnosticFilePath does not exist"
}

# Step 7: Check user profile integrity
Write-Log "Checking user profile integrity for current user"
$UserProfile = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)" -ErrorAction SilentlyContinue
if ($UserProfile) {
    Write-Log "User profile found. Profile path: $($UserProfile.ProfileImagePath)"
} else {
    Write-Log "WARNING: User profile not found in registry. This may indicate a corrupted profile."
}

# Step 8: Summarize findings
Write-Log "Diagnosis Summary:"
Write-Log "1. DPAPI errors are occurring every 5 minutes, indicating a recurring process."
if ($Events) {
    Write-Log "2. $($Events.Count) error events found. Check $EventLogCsv for details."
}
if (Test-Path $ProcMonLog) {
    Write-Log "3. Process Monitor log ($ProcMonLog) captured. Analyze it to identify the process triggering DPAPI calls."
}
Write-Log "4. Cryptographic Services status: $((Get-Service -Name 'CryptSvc').Status)"
Write-Log "5. Diagnostic files: $(if (Test-Path $DiagnosticFilePath) { 'Exist' } else { 'Not found' })"
Write-Log "6. User profile: $(if ($UserProfile) { 'Intact' } else { 'Potentially corrupted' })"
Write-Log "Next Steps:"
Write-Log "- Open $ProcMonLog in Process Monitor and filter for DPAPI-related operations (e.g., CryptUnprotectData) around error timestamps."
Write-Log "- Review diagnostic files in $DiagnosticFilePath for master key issues."
Write-Log "- If the issue persists, consider resetting the DPAPI master keys or repairing the user profile."
Write-Log "Diagnosis complete. Summary saved to $SummaryReport"