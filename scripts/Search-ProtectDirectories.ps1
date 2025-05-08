# Define the root path to search
$rootPath = "C:\"

# Log file for output
$logFile = "$env:TEMP\Protect_Subdirectory_Search_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Log-Output { param($Message) Write-Host $Message; $Message | Out-File -FilePath $logFile -Append }

# Initialize counter for found directories
$foundCount = 0

# Start the search
Log-Output "Searching for subdirectories exactly named 'Protect' (including hidden) on $rootPath..."
Log-Output "Start Time: $(Get-Date)"
Log-Output "------------------------"

try {
    # Search for directories exactly named 'Protect' (case-insensitive), including hidden/system
    $directories = Get-ChildItem -Path $rootPath -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "Protect" } |
        Select-Object FullName, CreationTime, LastWriteTime, Attributes

    if ($directories) {
        foreach ($dir in $directories) {
            $foundCount++
            Log-Output "Found Subdirectory: $($dir.FullName)"
            Log-Output "Created: $($dir.CreationTime)"
            Log-Output "Last Modified: $($dir.LastWriteTime)"
            Log-Output "Attributes: $($dir.Attributes)"
            Log-Output "------------------------"
        }
    } else {
        Log-Output "No subdirectories exactly named 'Protect' found on $rootPath."
    }
} catch {
    Log-Output "Error during search: $($_.Exception.Message)"
}

# Handle errors from inaccessible directories
$Error | Where-Object { $_ -like "*Access is denied*" } | ForEach-Object {
    Log-Output "Access Denied: $($_.TargetObject)"
}

# Final summary
Log-Output "------------------------"
Log-Output "Search completed at: $(Get-Date)"
Log-Output "Total 'Protect' subdirectories found: $foundCount"
Log-Output "Results saved to: $logFile"
Write-Host "Log file location: $logFile"