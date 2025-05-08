# PowerShell script to troubleshoot WMI-Activity errors on Lenovo laptop (Windows 11)
# Checks WMI repository, ArbTaskMaxIdle, WMI queries, resource usage, and system updates
# Run as Administrator

# Initialize log file
$logFile = "$env:USERPROFILE\WMI_Troubleshoot_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Host "$timestamp - $Message"
}

Write-Log "Starting WMI troubleshooting script"

# Ensure script runs with elevated privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: Script must be run as Administrator. Exiting."
    exit 1
}

# 1. Check WMI Repository
Write-Log "Checking WMI repository consistency..."
try {
    $verifyResult = & winmgmt /verifyrepository
    Write-Log "WMI Repository Check: $verifyResult"
    if ($verifyResult -like "*inconsistent*") {
        Write-Log "WARNING: WMI repository is inconsistent. Consider resetting it (manual step required)."
        Write-Log "To reset: Run 'net stop winmgmt', rename C:\Windows\System32\wbem\Repository, then 'net start winmgmt'."
    }
} catch {
    Write-Log "ERROR: Failed to verify WMI repository. Error: $_"
}

# 2. Check ArbTaskMaxIdle Registry Setting
Write-Log "Checking ArbTaskMaxIdle registry setting..."
$regPath = "HKLM:\SOFTWARE\Microsoft\WBEM\CIMOM"
$regKey = "ArbTaskMaxIdle"
try {
    if (Test-Path $regPath) {
        $value = Get-ItemProperty -Path $regPath -Name $regKey -ErrorAction SilentlyContinue
        if ($value) {
            Write-Log "ArbTaskMaxIdle is set to: $($value.$regKey)"
            if ($value.$regKey -lt 10) {
                Write-Log "NOTE: ArbTaskMaxIdle is low. Consider increasing it (e.g., double the value) after backing up registry."
            }
        } else {
            Write-Log "ArbTaskMaxIdle is not set (using default). No action needed unless issues persist."
        }
    } else {
        Write-Log "CIMOM registry path not found. ArbTaskMaxIdle likely using default settings."
    }
} catch {
    Write-Log "ERROR: Failed to check ArbTaskMaxIdle. Error: $_"
}

# 3. Run WMI Queries
Write-Log "Running WMI queries to test functionality..."
$queries = @(
    @{
        Namespace = "root\WMI"
        Query = "SELECT * FROM LENOVO_CAPABILITY_DATA_00"
    },
    @{
        Namespace = "ROOT\CIMV2"
        Query = "SELECT * FROM Win32_ComputerSystemProduct"
    },
    @{
        Namespace = "ROOT\CIMV2"
        Query = "SELECT * FROM Win32_DiskDrive WHERE DeviceID LIKE '%PHYSICALDRIVE0%'"
    },
    @{
        Namespace = "ROOT\CIMV2"
        Query = "SELECT * FROM Win32_PhysicalMemory WHERE Tag='Physical Memory 0'"
    }
)

foreach ($q in $queries) {
    Write-Log "Executing query: $($q.Query) in namespace $($q.Namespace)"
    try {
        $result = Get-WmiObject -Namespace $q.Namespace -Query $q.Query -ErrorAction Stop
        if ($result) {
            Write-Log "Query succeeded. Results returned: $($result.Count)"
        } else {
            Write-Log "Query returned no results."
        }
    } catch {
        Write-Log "ERROR: Query failed. Error: $_"
        if ($_.Exception.Message -like "*0x80041032*") {
            Write-Log "NOTE: Error 0x80041032 (WBEM_E_CALL_CANCELLED) indicates WMI throttling or cancellation."
        }
    }
}

# 4. Check System Resource Usage
Write-Log "Checking system resource usage..."
try {
    $cpu = Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average
    $memory = Get-CimInstance -ClassName Win32_OperatingSystem
    $disk = Get-Counter -Counter "\PhysicalDisk(_Total)\% Disk Time" -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
    $cpuUsage = $cpu.Average
    $memoryFree = [math]::Round($memory.FreePhysicalMemory / $memory.TotalVisibleMemorySize * 100, 2)
    $diskUsage = [math]::Round($disk.CounterSamples.CookedValue, 2)

    Write-Log "CPU Usage: $cpuUsage%"
    Write-Log "Memory Free: $memoryFree% ($([math]::Round($memory.FreePhysicalMemory/1024, 2)) MB free)"
    Write-Log "Disk Activity: $diskUsage%"
    
    if ($cpuUsage -gt 80) { Write-Log "WARNING: High CPU usage may contribute to WMI throttling." }
    if ($memoryFree -lt 20) { Write-Log "WARNING: Low memory may contribute to WMI issues." }
    if ($diskUsage -gt 80) { Write-Log "WARNING: High disk activity may contribute to WMI throttling." }
} catch {
    Write-Log "ERROR: Failed to check system resources. Error: $_"
}

# 5. Check Lenovo Services
Write-Log "Checking Lenovo-related services..."
$lenovoServices = @("LenovoVantageService", "LenovoUtilityService", "LenovoService")
foreach ($service in $lenovoServices) {
    try {
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log "Service $service found. Status: $($svc.Status), StartupType: $($svc.StartType)"
        } else {
            Write-Log "Service $service not found."
        }
    } catch {
        Write-Log "ERROR: Failed to check service $service. Error: $_"
    }
}

# 6. Check Windows Update Status
Write-Log "Checking Windows Update status..."
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $updates = $updateSearcher.Search("IsInstalled=0")
    if ($updates.Updates.Count -gt 0) {
        Write-Log "WARNING: $($updates.Updates.Count) pending Windows updates found. Install via Settings > Windows Update."
    } else {
        Write-Log "No pending Windows updates found."
    }
} catch {
    Write-Log "ERROR: Failed to check Windows updates. Error: $_"
}

Write-Log "NOTE: Check Lenovo Vantage for software/driver updates. Run Vantage or visit Lenovo's support site."

# 7. Check Lenovo WMI Service in Device Manager
Write-Log "Checking Lenovo WMI Service in Device Manager..."
try {
    $wmiService = Get-PnpDevice | Where-Object { $_.Name -like '*Lenovo WMI Service*' }
    if ($wmiService) {
        Write-Log "Lenovo WMI Service found. Status: $($wmiService.Status)"
        if ($wmiService.Status -ne 'OK') {
            Write-Log "WARNING: Lenovo WMI Service is not functioning properly. Check Device Manager."
        }
    } else {
        Write-Log "Lenovo WMI Service not found in Device Manager."
    }
} catch {
    Write-Log "ERROR: Failed to check Lenovo WMI Service. Error: $_"
}

# 8. Final Guidance
Write-Log "Troubleshooting complete. Review the log at: $logFile"
Write-Log "Next steps if errors persist:"
Write-Log "- Update Lenovo Vantage and drivers via Lenovo's support site."
Write-Log "- Reset WMI repository (see instructions above)."
Write-Log "- Adjust ArbTaskMaxIdle in registry (backup first)."
Write-Log "- Contact Lenovo support with this log and event details."

Write-Host "Script completed. Log saved to: $logFile"