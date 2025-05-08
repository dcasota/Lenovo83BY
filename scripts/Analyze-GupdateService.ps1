# Analyze-GupdateService.ps1
# PowerShell script to analyze and fix Google Update Service (gupdate) timeout issues

# Requires elevated privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "This script requires administrative privileges. Please run as Administrator." -ForegroundColor Red
    exit 1
}

# Function to analyze the gupdate service
function Analyze-GupdateService {
    Write-Host "Analyzing Google Update Service (gupdate)..." -ForegroundColor Cyan

    # Check if service exists
    $service = Get-Service -Name "gupdate" -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "Google Update Service (gupdate) not found on this system." -ForegroundColor Yellow
        return $false
    }

    # Get service status and configuration
    Write-Host "`nService Status:" -ForegroundColor Green
    Write-Host "Name: $($service.Name)"
    Write-Host "Display Name: $($service.DisplayName)"
    Write-Host "Status: $($service.Status)"
    Write-Host "Start Type: $($service.StartType)"

    # Get service details via WMI
    $wmiService = Get-WmiObject -Class Win32_Service -Filter "Name='gupdate'"
    Write-Host "`nService Configuration:" -ForegroundColor Green
    Write-Host "Path: $($wmiService.PathName)"
    Write-Host "Service Account: $($wmiService.StartName)"

    # Check recent event logs for gupdate errors
    Write-Host "`nRecent Event Log Errors for gupdate:" -ForegroundColor Green
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'System'
        ProviderName = 'Service Control Manager'
        Level = 2 # Error
        ID = 7000, 7011 # Service startup failure, timeout
    } -MaxEvents 10 -ErrorAction SilentlyContinue | Where-Object { $_.Message -like "*gupdate*" }

    if ($events) {
        foreach ($event in $events) {
            Write-Host "Event ID: $($event.Id), Time: $($event.TimeCreated), Message: $($event.Message)"
        }
    } else {
        Write-Host "No recent error events found for gupdate."
    }

    # Check service timeout settings in registry
    $timeoutRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
    $timeoutValue = (Get-ItemProperty -Path $timeoutRegPath -Name "ServicesPipeTimeout" -ErrorAction SilentlyContinue).ServicesPipeTimeout
    Write-Host "`nService Timeout Configuration:" -ForegroundColor Green
    if ($timeoutValue) {
        Write-Host "ServicesPipeTimeout: $($timeoutValue) milliseconds"
    } else {
        Write-Host "ServicesPipeTimeout: Default (30000 ms)"
    }

    return $true
}

# Function to fix gupdate service issues
function Fix-GupdateService {
    param (
        [switch]$IncreaseTimeout,
        [switch]$ResetService,
        [switch]$DisableService
    )

    Write-Host "`nApplying Fixes for Google Update Service..." -ForegroundColor Cyan

    # Increase service timeout
    if ($IncreaseTimeout) {
        $timeoutRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control"
        $newTimeout = 120000 # 120 seconds
        Write-Host "Increasing service timeout to $newTimeout milliseconds..."
        Set-ItemProperty -Path $timeoutRegPath -Name "ServicesPipeTimeout" -Value $newTimeout -Type DWord -ErrorAction Stop
        Write-Host "Service timeout increased successfully." -ForegroundColor Green
    }

    # Reset service configuration
    if ($ResetService) {
        Write-Host "Resetting gupdate service configuration..."
        try {
            # Stop the service if running
            Stop-Service -Name "gupdate" -Force -ErrorAction SilentlyContinue
            # Reset service to default settings
            $servicePath = '"C:\Program Files (x86)\Google\Update\GoogleUpdate.exe" /svc'
            Set-Service -Name "gupdate" -StartupType Automatic -ErrorAction Stop
            sc.exe config gupdate binPath= $servicePath | Out-Null
            Write-Host "Service configuration reset successfully." -ForegroundColor Green
        } catch {
            Write-Host "Error resetting service: $_" -ForegroundColor Red
        }
    }

    # Disable service
    if ($DisableService) {
        Write-Host "Disabling gupdate service..."
        try {
            Stop-Service -Name "gupdate" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "gupdate" -StartupType Disabled -ErrorAction Stop
            Write-Host "Service disabled successfully." -ForegroundColor Green
        } catch {
            Write-Host "Error disabling service: $_" -ForegroundColor Red
        }
    }
}

# Main script execution
Write-Host "Google Update Service (gupdate) Analysis and Fix Tool" -ForegroundColor Cyan
Write-Host "----------------------------------------------------"

# Analyze the service
$serviceExists = Analyze-GupdateService

if ($serviceExists) {
    # Prompt user for fix options
    Write-Host "`nAvailable Fix Options:" -ForegroundColor Cyan
    Write-Host "1. Increase service timeout to 120 seconds"
    Write-Host "2. Reset service configuration"
    Write-Host "3. Disable service"
    Write-Host "4. Apply all fixes"
    Write-Host "5. Exit without changes"

    $choice = Read-Host "`nEnter option (1-5)"
    
    switch ($choice) {
        "1" { Fix-GupdateService -IncreaseTimeout }
        "2" { Fix-GupdateService -ResetService }
        "3" { Fix-GupdateService -DisableService }
        "4" { Fix-GupdateService -IncreaseTimeout -ResetService }
        "5" { Write-Host "Exiting without changes." -ForegroundColor Yellow }
        default { Write-Host "Invalid option. Exiting." -ForegroundColor Red }
    }
}

Write-Host "`nScript execution completed." -ForegroundColor Cyan