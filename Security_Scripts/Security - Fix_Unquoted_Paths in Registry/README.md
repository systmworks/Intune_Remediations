<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Fix Unquoted Paths in Registry

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Unquoted_Paths_DETECT.ps1

Scans `ImagePath` and `UninstallString` values under HKLM Services and Uninstall keys (including Wow6432Node) for executable paths that contain spaces but are not wrapped in double quotes — a common privilege-escalation vector (CWE-428). Matching entries are logged to `C:\Windows\Temp\Fix_Unquoted_Paths.csv`. Exits **1** when unquoted paths are found; **0** when none.

Detection does not modify registry values.

## PS_Unquoted_Paths_REMEDIATE.ps1

Finds the same unquoted `ImagePath` and `UninstallString` values and wraps the executable portion in double quotes while preserving trailing arguments. Handles both plain and ExpandString registry types using the unexpanded value where needed.

Run after the detect script flags non-compliance to close unquoted service path findings from security scanners.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

