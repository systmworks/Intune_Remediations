<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>
# Delete OST Files Older Than 30 Days

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_OST_Files_Older_30_Days_DETECT.ps1

Scans `C:\Users\*\AppData\Local\Microsoft\Outlook\*.ost` across all user profiles and flags OST files whose last write time is older than 30 days. Reports the count of stale files and total size in GB. Exits **1** when stale OST files exist; **0** when none are found.

Useful for reclaiming disk space from abandoned or stale Outlook cached mailboxes.

## PS_OST_Files_Older_30_Days_REMEDIATE.ps1

Removes Outlook OST files that have not been modified in over 30 days, using the same profile-wide search path as the detect script. Files are force-deleted when remediation runs.

Ensure users are not actively using affected mailboxes before deploying; stale OST removal can require Outlook to rebuild the cache.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.