# Install-VCRedist.ps1
# Downloads and installs Microsoft Visual C++ Redistributable (x86 and x64) for 2015-2022

# Requires elevated privileges
#Requires -RunAsAdministrator

# Set up logging
$logFile = "$env:TEMP\VCRedist_Install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
function Write-Log {
    param($Message)
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Output $logMessage | Out-File -FilePath $logFile -Append
    Write-Host $logMessage
}

Write-Log "Starting Visual C++ Redistributable installation script"

# Define download URLs for VC++ Redistributables (latest as of 2025)
$vcRedistUrls = @{
    "x86" = "https://aka.ms/vs/17/release/vc_redist.x86.exe"
    "x64" = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

# Define temp download path
$tempPath = "$env:TEMP\VCRedist"
if (-not (Test-Path $tempPath)) {
    New-Item -ItemType Directory -Path $tempPath | Out-Null
}

# Function to check if VC++ Redistributable is already installed
function Test-VCRedistInstalled {
    param($Architecture)
    $installed = Get-WmiObject Win32_Product | Where-Object {
        $_.Name -like "*Visual C++*Redistributable*$Architecture*" -and $_.Version -ge "14.32.31332"
    }
    return $null -ne $installed
}

# Download and install VC++ Redistributables
foreach ($arch in $vcRedistUrls.Keys) {
    $url = $vcRedistUrls[$arch]
    $fileName = "vc_redist.$arch.exe"
    $filePath = Join-Path $tempPath $fileName

    # Check if already installed
    if (Test-VCRedistInstalled -Architecture $arch) {
        Write-Log "Visual C++ Redistributable ($arch) version 14.32.31332 or higher is already installed. Skipping."
        continue
    }

    # Download the installer
    Write-Log "Downloading Visual C++ Redistributable ($arch) from $url"
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($url, $filePath)
        Write-Log "Download completed: $filePath"
    }
    catch {
        Write-Log "Error downloading $fileName : $($_.Exception.Message)"
        continue
    }

    # Install the redistributable
    Write-Log "Installing Visual C++ Redistributable ($arch)"
    try {
        $installArgs = "/install /quiet /norestart"
        $process = Start-Process -FilePath $filePath -ArgumentList $installArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log "Installation of $fileName completed successfully"
        }
        else {
            Write-Log "Installation of $fileName failed with exit code $($process.ExitCode)"
        }
    }
    catch {
        Write-Log "Error installing $fileName : $($_.Exception.Message)"
    }

    # Clean up
    Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
}

# Verify installation
Write-Log "Verifying installed Visual C++ Redistributables"
$installedRedists = Get-WmiObject Win32_Product | Where-Object {
    $_.Name -like "*Visual C++*Redistributable*"
} | Select-Object Name, Version, InstallDate

foreach ($redist in $installedRedists) {
    Write-Log "Found: $($redist.Name), Version: $($redist.Version), Installed: $($redist.InstallDate)"
}

Write-Log "Script execution completed. Log file: $logFile"

# Clean up temp directory
Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue