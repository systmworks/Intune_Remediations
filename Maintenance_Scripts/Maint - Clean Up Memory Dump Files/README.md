<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>
# Clean Up Memory Dump Files

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Memory_Dump_Files_DETECT_v1.4.ps1

Scans configured dump locations for files older than 7 days, including `%windir%\memory.dmp`, minidumps, per-user CrashDumps folders, and VMware/Horizon dump paths. When stale dumps are found, it reports the total size in GB and exits **1** so Intune triggers remediation; otherwise exits **0**.

Detection is age-only (no minimum size threshold). Output is written to the Intune Management Extension log folder via transcript.

## PS_Memory_Dump_Files_REMEDIATE_v1.4.ps1

Removes the same dump file set as the detect script when files are older than 7 days. Targets system memory dumps, minidumps, user CrashDumps, and VMware/Horizon dump folders using the shared path list.

Runs silently with transcript logging. Use after the detect script flags non-compliance.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.