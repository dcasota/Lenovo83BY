# Get the current date and time
$currentTime = Get-Date

# Calculate the time 5 minutes ago
$startTime = $currentTime.AddMinutes(-5)

# Get all available event log names
$eventLogs = Get-WinEvent -ListLog * | Select-Object -ExpandProperty LogName

# Iterate through each log and analyze events from the last 5 minutes
foreach ($logName in $eventLogs) {
    try {
        # Write-Host "Checking log: $logName"

        try {
        $events = Get-WinEvent -LogName $logName -ErrorAction Stop
	}
	catch {continue}

        if ($events)
	{
        $matchingEvents = $events | Where-Object { $_.TimeCreated -ge $startTime -and $_.LevelDisplayName -eq "Error" }

        # Output results only if matching events are found
        if ($matchingEvents) {
            Write-Host "Errors found in log: $logName"
            $matchingEvents | Select-Object TimeCreated, Message | Format-Table -AutoSize
        }
	}
    } catch {
        # Handle failed queries and suppressed errors gracefully
        Write-Host "Log: $logName could not be queried or contains no events."
        continue
    }
}
