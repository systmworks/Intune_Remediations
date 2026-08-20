<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>
# Extend C Partition to Max Size

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Unallocated_Disk_Space_DETECT_v1.1.ps1

Rescans disks and compares the physical disk size hosting drive C: against the C: partition size. Exits **1** when unallocated space exists on that disk (C: can be extended); **0** when C: already uses all available space. Uses the C: partition's `DiskNumber` so it works on VMs and multi-disk hosts.

## PS_Unallocated_Disk_Space_REMEDIATE_v1.1.ps1

Extends the C: partition into unallocated space on the same disk. If a small partition immediately after C: is provably blocking extension (same disk, after C:, ≤1 GB, not EFI or Microsoft Reserved), it removes that partition first, then grows C:.

Includes try/catch and skip logic when no action is needed. A reboot is not typically required for partition extension.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.