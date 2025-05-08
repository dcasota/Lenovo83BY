# Analyze_AMD_DPFC_Service_Issue.ps CTS
# PowerShell script to diagnose and optionally fix the amd_dpfc service failure in Windows 11
# Requires administrative privileges

# Ensure the script runs with elevated privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires administrative privileges. Please run as Administrator." -ForegroundColor Red
    exit
}

# Initialize variables
$serviceName = "amd_dpfc"
$logName = "System"
$source = "Service Control Manager"
$maxEvents = 5
$logFile = "$env:TEMP\amd_dpfc_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

# Function to write to both console and log file
function Write-Log {
    param($Message, $Color = "White")
    Write-Host $Message -ForegroundColor $Color
    $Message | Out-File -FilePath $logFile -Append
}

# Start logging
Write-Log "=== AMD DPFC Service Failure Analysis ===`n" -Color Cyan
Write-Log "Date: $(Get-Date)"
Write-Log "Log File: $logFile`n"

# Step 1: Check if the amd_dpfc service exists and its status
Write-Log "Checking for $serviceName service..."
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Log "Service Found: $serviceName"
    Write-Log "Status: $($service.Status)"
    Write-Log "Startup Type: $($service.StartType)"
} else {
    Write-Log "Service $serviceName not found. It may have been removed or never installed." -Color Yellow
    Write-Log "This could indicate an incomplete AMD driver installation or manual removal."
}

# Step 2: Retrieve recent System Event Log entries for amd_dpfc failures
Write-Log "`nRetrieving recent System Event Log entries for $serviceName (max $maxEvents)..."
try {
    $events = Get-WinEvent -LogName $logName -FilterHashtable @{
        ProviderName = $source
        ID = 7000, 7001, 7023  # Service failure-related event IDs
    } -MaxEvents $maxEvents -ErrorAction Stop | Where-Object { $_.Message -like "*$serviceName*" }
    
    if ($events) {
        Write-Log "Found $($events.Count) relevant event(s):"
        foreach ($event in $events) {
            Write-Log "-------------------------"
            Write-Log "Time: $($event.TimeCreated)"
            Write-Log "Event ID: $($event.Id)"
            Write-Log "Level: $($event.LevelDisplayName)"
            Write-Log "Message: $($event.Message)"
        }
    } else {
        Write-Log "No recent events found for $serviceName in $logName log." -Color Yellow
    }
} catch {
    Write-Log "Error retrieving event logs: $_" -Color Red
}

# Step 3: Check AMD driver information
Write-Log "`nChecking AMD driver information..."
$amdDrivers = Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.Manufacturer -like "*AMD*" -or $_.Description -like "*AMD*" }
if ($amdDrivers) {
    Write-Log "Found AMD drivers:"
    foreach ($driver in $amdDrivers) {
        Write-Log "Device: $($driver.DeviceName)"
        Write-Log "Driver Version: $($driver.DriverVersion)"
        Write-Log "Driver Date: $($driver.DriverDate)"
        Write-Log "-------------------------"
    }
} else {
    Write-Log "No AMD drivers found. This may indicate a driver installation issue." -Color Yellow
}

# Step 4: Provide diagnostic summary and fix options
Write-Log "`n=== Diagnostic Summary ===" -Color Cyan
if ($service) {
    if ($service.Status -ne "Running") {
        Write-Log "The $serviceName service is not running (Current Status: $($service.Status))."
    } else {
        Write-Log "The $serviceName service is running, but past failures were detected."
    }
} else {
    Write-Log "The $serviceName service is missing, which may prevent proper AMD functionality."
}

Write-Log "`n=== Recommended Fix Options ===" -Color Green
Write-Log "1. Update/Reinstall AMD Drivers:"
Write-Log "   - Download the latest AMD chipset/GPU drivers from https://www.amd.com/en/support."
Write-Log "   - Use AMD Cleanup Utility (https://www.amd.com/en/resources/support-articles/faqs/GPU-601.html) to remove existing drivers."
Write-Log "   - Install the latest drivers and reboot."
Write-Log "2. Check System Files:"
Write-Log "   - Run: DISM.exe /Online /Cleanup-Image /RestoreHealth"
Write-Log "   - Run: sfc /scannow"
Write-Log "   - Reboot after completion."
Write-Log "3. Disable $serviceName Service (if not critical):"
Write-Log "   - Run: Set-Service -Name $serviceName -StartupType Disabled"
Write-Log "   - Note: This may impact AMD-specific features; use cautiously."
Write-Log "4. Check for Windows Updates:"
Write-Log "   - Go to Settings > Windows Update > Check for updates."
Write-Log "   - Install any pending updates and reboot."

# Step 5: Prompt user for automated fix (optional)
Write-Log "`nWould you like to attempt an automated fix? (Select an option below)" -Color Yellow
Write-Log "1. Run DISM and SFC (System File Check)"
Write-Log "2. Disable $serviceName service"
Write-Log "3. Skip automated fix"
$choice = Read-Host "Enter choice (1, 2, or 3)"

switch ($choice) {
    "1" {
        Write-Log "`nRunning DISM and SFC..."
        try {
            Write-Log "Executing: DISM.exe /Online /Cleanup-Image /RestoreHealth"
            Start-Process -FilePath "DISM.exe" -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -Wait -NoNewWindow
            Write-Log "DISM completed."
            Write-Log "Executing: sfc /scannow"
            Start-Process -FilePath "sfc.exe" -ArgumentList "/scannow" -Wait -NoNewWindow
            Write-Log "SFC completed. Please reboot your system."
        } catch {
            Write-Log "Error running DISM/SFC: $_" -Color Red
        }
    }
    "2" {
        if ($service) {
            Write-Log "`nDisabling $serviceName service..."
            try {
                Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
                Write-Log "$serviceName service disabled successfully."
            } catch {
                Write-Log "Error disabling service: $_" -Color Red
            }
        } else {
            Write-Log "$serviceName service not found; cannot disable." -Color Yellow
        }
    }
    "3" {
        Write-Log "Skipping automated fix."
    }
    default {
        Write-Log "Invalid choice. Skipping automated fix." -Color Yellow
    }
}

# Final instructions
Write-Log "`n=== Next Steps ===" -Color Cyan
Write-Log "1. Review the log file: $logFile"
Write-Log "2. Reboot your system if any fixes were applied."
Write-Log "3. If the issue persists, contact AMD support or check forums like https://community.amd.com/"
Write-Log "Analysis complete.`n" -Color Green