<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>
# Remove Outdated ASP.NET Runtimes (v1–v10)

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_ASP_NET_Core_Runtimes_DETECT.ps1

Detects EOL or outdated ASP.NET Core runtimes (v1–v10) via registry and on-disk shared-framework folders. Flags outdated v8/v9/v10 only when a supported minimum version is already installed on the same machine. Exits **1** when runtimes should be removed; **0** when compliant.

## PS_ASP_NET_Core_Runtimes_REMEDIATE.ps1

Uninstalls EOL ASP.NET Core runtimes via `msiexec` using registered MSI product codes, which clears Programs & Features and Uninstall registry entries that vulnerability scanners read. Outdated v8/v9/v10 are removed only when a supported version remains. Falls back to forced folder delete only for orphaned installs with no registry entry (logged separately).

Processes all x64 and x86 registry entries in a single run. Does not force-delete folders left after a successful msiexec uninstall in the same pass.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.