<########################################################
    Name:      PS_Memory_Dump_Files_REMEDIATE.ps1
    Purpose:   Remove Windows memory dump files (system + user crash dumps)
               older than 7 days.
    Location:  Intune
    Owner:     Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        26/05/2025 - v1.0 - Initial Remediation Script (simplified output)
        12/03/2026 - v1.3 - Streamlined using array with wildcards for all paths
        12/03/2026 - v1.4 - Added VMware dump folders
########################################################>

# Start transcript (best-effort; don't break if this fails)
try {
    Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Memory_Dump_Files_REMEDIATE.log" -ErrorAction SilentlyContinue
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

$FailedRemovals = 0

# --- Process all dump paths ---
foreach ($Path in $DumpPaths) {
    $files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        if ($file.LastWriteTime -lt $CutoffDate) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            } catch {
                $FailedRemovals++
                Write-Error "Failed to remove: $($file.FullName) - Error: $($_.Exception.Message)"
            }
        }
    }
}

try {
    Stop-Transcript | Out-Null
} catch { }

# Exit with error code if any removals failed
exit $FailedRemovals
