<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Remove Outdated .NET Runtimes

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_NET_Runtimes_DETECT.ps1

Detects end-of-life or outdated .NET Runtime and Windows Desktop Runtime installations using HKLM Uninstall registry keys plus an orphan folder scan for on-disk runtimes without registry entries. Also evaluates Host FX Resolver and .NET Host companions (the highest version of each component is never flagged). When a .NET SDK is present, only EOL majors (1–7) are flagged; outdated v8/v9/v10 are exempt. Exits **1** when removable runtimes are found.

## PS_NET_Runtimes_REMEDIATE.ps1

Removes EOL or outdated .NET Runtime and Windows Desktop Runtime in a single coordinated pass. Desktop Runtime is removed before .NET Runtime to respect dependency order. Host FX Resolver and .NET Host companions are removed only when a strictly higher version remains on the machine.

Designed to reduce vulnerability scanner noise from stale runtime versions while preserving what applications still need.

---

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

