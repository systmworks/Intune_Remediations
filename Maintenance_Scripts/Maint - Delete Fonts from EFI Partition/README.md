<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Delete Fonts from EFI Partition

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Delete_EFI_Fonts_DETECT.ps1

Mounts the EFI partition and checks for font files that can be safely removed to reclaim approximately 17 MB of space on the EFI volume. Exits **1** when removable fonts are present so Intune can run the remediate script; exits **0** when none are found.

## PS_Delete_EFI_Fonts_REMEDIATE.ps1

Mounts the EFI partition and deletes the font files identified by the detect script. These fonts are not required for normal boot and removal is safe on supported hardware.

Run as part of a proactive remediation pair after detection flags non-compliance.

---

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

