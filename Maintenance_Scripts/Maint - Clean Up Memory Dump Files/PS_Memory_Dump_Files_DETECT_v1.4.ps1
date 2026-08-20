<########################################################
    Name:      PS_Memory_Dump_Files_DETECT.ps1
    Purpose:   Detect if Windows Memory dump files (system + user crash dumps)
               are older than 7 days, to trigger optional removal.
               Reports total size (GB) of files older than 7 days.
    Location:  Intune
    Owner:     Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        26/05/2025 - v1.0 - New Script developed
        23/02/2026 - v1.1 - Added user profile CrashDumps detection
        23/02/2026 - v1.2 - Removed size threshold; age-only detection, report GB of old files
        12/03/2026 - v1.3 - Streamlined using array with wildcards for all paths
        12/03/2026 - v1.4 - Added VMware dump folders
########################################################>

# Start transcript (best-effort; don't break if this fails)
try {
    Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Memory_Dump_Files_DETECT.log" -ErrorAction SilentlyContinue
} catch { }

# Thresholds
$MaxAgeDays = 7
$CutoffDate = (Get-Date).AddDays(-$MaxAgeDays)

# Define all dump file locations (files and folders with wildcards)
$DumpPaths = @(
    "$env:windir\memory.dmp",
    "$env:windir\minidump\*",
    "C:\Windows\System32\config\systemprofile\AppData\Local\CrashDumps\*",
    "C:\Users\*\AppData\Local\CrashDumps\*",
    "C:\ProgramData\Omnissa\Horizon\Dumps\*",
    "C:\ProgramData\VMware\VDM\Dumps\*"
)

# Total size of files that are older than the threshold
$OldFilesTotalSizeBytes = 0
$AnyOldFiles            = $false

# --- Process all dump paths ---
foreach ($Path in $DumpPaths) {
    $files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($file.LastWriteTime -lt $CutoffDate) {
            $OldFilesTotalSizeBytes += $file.Length
            $AnyOldFiles = $true
        }
    }
}

# Convert total size of old files to GB (rounded to 1 decimal)
$OldFilesTotalSizeGB = [math]::Round($OldFilesTotalSizeBytes / 1GB, 1)

# Output and exit code for Intune detection
if ($AnyOldFiles) {
    Write-Host "Found $($OldFilesTotalSizeGB) GB of Dump files older than $($MaxAgeDays) days." -Foregroundcolor Yellow
    $exitCode = 1
} else {
    Write-Host "No dump files older than $($MaxAgeDays) days detected." -Foregroundcolor Green
    $exitCode = 0
}

try {
    Stop-Transcript | Out-Null
} catch { }

exit $exitCode
