# Define the directory path
$directoryPath = "C:\Users\dcaso\AppData\Roaming\Microsoft\Protect\S-1-5-21-424017375-788226864-4025993240-1001"

# Log file for output
$logFile = "$env:TEMP\Permissions_Check_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
function Log-Output { param($Message) Write-Host $Message; $Message | Out-File -FilePath $logFile -Append }

# Function to enable privileges
function Enable-Privilege {
    param($Privilege)
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class Privilege {
        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);
        [StructLayout(LayoutKind.Sequential)]
        public struct TOKEN_PRIVILEGES {
            public uint PrivilegeCount;
            public LUID Luid;
            public uint Attributes;
        }
        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int HighPart;
        }
        public const uint SE_PRIVILEGE_ENABLED = 0x00000002;
        public const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
        public const uint TOKEN_QUERY = 0x0008;
    }
"@
    $processHandle = [System.Diagnostics.Process]::GetCurrentProcess().Handle
    $tokenHandle = [IntPtr]::Zero
    if (-not [Privilege]::OpenProcessToken($processHandle, [Privilege]::TOKEN_ADJUST_PRIVILEGES -bor [Privilege]::TOKEN_QUERY, [ref]$tokenHandle)) {
        return $false
    }
    $tp = New-Object Privilege+TOKEN_PRIVILEGES
    $tp.PrivilegeCount = 1
    $tp.Attributes = [Privilege]::SE_PRIVILEGE_ENABLED
    if (-not [Privilege]::LookupPrivilegeValue($null, $Privilege, [ref]$tp.Luid)) {
        return $false
    }
    if (-not [Privilege]::AdjustTokenPrivileges($tokenHandle, $false, [ref]$tp, 0, [IntPtr]::Zero, [IntPtr]::Zero)) {
        return $false
    }
    return $true
}

# Enable necessary privileges
Log-Output "Enabling SeTakeOwnershipPrivilege and SeRestorePrivilege..."
$success = Enable-Privilege -Privilege "SeTakeOwnershipPrivilege"
Log-Output "SeTakeOwnershipPrivilege enabled: $success"
$success = Enable-Privilege -Privilege "SeRestorePrivilege"
Log-Output "SeRestorePrivilege enabled: $success"

# Check if running as administrator
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
Log-Output "Current User: $($currentUser.Name)"
Log-Output "Is Administrator: $isAdmin"

# Check domain connectivity
Log-Output "Checking domain connectivity..."
try {
    $dc = (Get-ADDomainController -Discover -Service PrimaryDC -ErrorAction Stop).HostName
    $pingResult = Test-Connection -ComputerName $dc -Count 2 -Quiet
    Log-Output "Domain Controller ($dc) reachable: $pingResult"
} catch {
    Log-Output "Error checking domain connectivity: $($_.Exception.Message)"
}

# Check if the directory exists
Log-Output "Checking permissions for files in: $directoryPath"
if (-not (Test-Path $directoryPath)) {
    Log-Output "Directory not found: ${directoryPath}"
    Write-Host "Log file location: $logFile"
    exit
}

# Get all files in the directory
try {
    $files = Get-ChildItem -Path $directoryPath -Force -File -ErrorAction Stop
    if ($files.Count -eq 0) {
        Log-Output "No files found in ${directoryPath}"
    } else {
        foreach ($file in $files) {
            Log-Output "File: $($file.FullName)"
            Log-Output "Attributes: $($file.Attributes)"
            Log-Output "Size: $($file.Length) bytes"
            Log-Output "Last Modified: $($file.LastWriteTime)"
            try {
                $acl = Get-Acl -Path $file.FullName -ErrorAction Stop
                if ($acl.Access.Count -gt 0) {
                    Log-Output "Permissions (Get-Acl):"
                    $acl.Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize | Out-String | Log-Output
                } else {
                    Log-Output "No permissions retrieved (empty ACL via Get-Acl)"
                }
                # Use icacls as a fallback
                Log-Output "Permissions (icacls):"
                $icaclsOutput = icacls $file.FullName
                $icaclsOutput | ForEach-Object { Log-Output $_ }
            } catch {
                Log-Output "Error retrieving permissions for $($file.FullName): $($_.Exception.Message)"
                # Attempt to take ownership
                Log-Output "Attempting to take ownership of $($file.FullName)"
                try {
                    $acl = New-Object System.Security.AccessControl.FileSecurity
                    $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544") # Administrators
                    $acl.SetOwner($adminSid)
                    Set-Acl -Path $file.FullName -AclObject $acl -ErrorAction Stop
                    Log-Output "Ownership taken. Retrying permissions..."
                    try {
                        $acl = Get-Acl -Path $file.FullName -ErrorAction Stop
                        if ($acl.Access.Count -gt 0) {
                            Log-Output "Permissions after taking ownership (Get-Acl):"
                            $acl.Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize | Out-String | Log-Output
                        } else {
                            Log-Output "Still no permissions retrieved after taking ownership (Get-Acl)"
                        }
                        $icaclsOutput = icacls $file.FullName
                        Log-Output "Permissions after taking ownership (icacls):"
                        $icaclsOutput | ForEach-Object { Log-Output $_ }
                    } catch {
                        Log-Output "Error retrieving permissions after ownership: $($_.Exception.Message)"
                    }
                    # Restore permissions
                    Log-Output "Restoring permissions for $($file.FullName)"
                    try {
                        $acl = Get-Acl $file.FullName -ErrorAction Stop
                        $dcasoSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-424017375-788226864-4025993240-1001")
                        $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18") # SYSTEM
                        $rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule($dcasoSid, "FullControl", "Allow")
                        $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", "Allow")
                        $acl.AddAccessRule($rule1)
                        $acl.AddAccessRule($rule2)
                        Set-Acl -Path $file.FullName -AclObject $acl -ErrorAction Stop
                        Log-Output "Permissions restored: dcaso and SYSTEM have FullControl"
                        $icaclsOutput = icacls $file.FullName
                        Log-Output "Final permissions (icacls):"
                        $icaclsOutput | ForEach-Object { Log-Output $_ }
                    } catch {
                        Log-Output "Error restoring permissions: $($_.Exception.Message)"
                    }
                } catch {
                    Log-Output "Error taking ownership: $($_.Exception.Message)"
                }
            }
            Log-Output "------------------------"
        }
    }
} catch {
    Log-Output "Error accessing directory ${directoryPath}: $($_.Exception.Message)"
}

# Check and fix permissions for the directory
Log-Output "Permissions for directory: $directoryPath"
try {
    $dirAcl = Get-Acl -Path $directoryPath -ErrorAction Stop
    if ($dirAcl.Access.Count -gt 0) {
        Log-Output "Directory Permissions (Get-Acl):"
        $dirAcl.Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize | Out-String | Log-Output
    } else {
        Log-Output "No permissions retrieved for directory (empty ACL via Get-Acl)"
    }
    $icaclsOutput = icacls $directoryPath
    Log-Output "Directory Permissions (icacls):"
    $icaclsOutput | ForEach-Object { Log-Output $_ }
} catch {
    Log-Output "Error retrieving directory permissions: $($_.Exception.Message)"
    Log-Output "Attempting to take ownership of ${directoryPath}"
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $adminSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544") # Administrators
        $acl.SetOwner($adminSid)
        Set-Acl -Path $directoryPath -AclObject $acl -ErrorAction Stop
        Log-Output "Ownership taken. Retrying permissions..."
        try {
            $acl = Get-Acl -Path $directoryPath -ErrorAction Stop
            if ($acl.Access.Count -gt 0) {
                Log-Output "Directory Permissions after taking ownership (Get-Acl):"
                $acl.Access | Format-Table IdentityReference, FileSystemRights, AccessControlType -AutoSize | Out-String | Log-Output
            } else {
                Log-Output "Still no permissions retrieved after taking ownership (Get-Acl)"
            }
            $icaclsOutput = icacls $directoryPath
            Log-Output "Directory Permissions after taking ownership (icacls):"
            $icaclsOutput | ForEach-Object { Log-Output $_ }
        } catch {
            Log-Output "Error retrieving directory permissions after ownership: $($_.Exception.Message)"
        }
        # Restore permissions
        Log-Output "Restoring permissions for ${directoryPath}"
        try {
            $acl = Get-Acl $directoryPath -ErrorAction Stop
            $dcasoSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-424017375-788226864-4025993240-1001")
            $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18") # SYSTEM
            $rule1 = New-Object System.Security.AccessControl.FileSystemAccessRule($dcasoSid, "FullControl", "Allow")
            $rule2 = New-Object System.Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", "Allow")
            $acl.AddAccessRule($rule1)
            $acl.AddAccessRule($rule2)
            Set-Acl -Path $directoryPath -AclObject $acl -ErrorAction Stop
            Log-Output "Permissions restored: dcaso and SYSTEM have FullControl"
            $icaclsOutput = icacls $directoryPath
            Log-Output "Final directory permissions (icacls):"
            $icaclsOutput | ForEach-Object { Log-Output $_ }
        } catch {
            Log-Output "Error restoring directory permissions: $($_.Exception.Message)"
        }
    } catch {
        Log-Output "Error taking ownership of directory: $($_.Exception.Message)"
    }
}

# Test DPAPI functionality
Log-Output "Testing DPAPI functionality..."
try {
    $data = [System.Text.Encoding]::UTF8.GetBytes("TestData")
    $protectedData = [System.Security.Cryptography.ProtectedData]::Protect($data, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    Log-Output "DPAPI Protect succeeded."
    $unprotectedData = [System.Security.Cryptography.ProtectedData]::Unprotect($protectedData, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    Log-Output "DPAPI Unprotect succeeded."
} catch {
    Log-Output "DPAPI operation failed: $($_.Exception.Message)"
}

# Save log
Log-Output "Permission check complete. Results saved to $logFile"
Write-Host "Log file location: $logFile"