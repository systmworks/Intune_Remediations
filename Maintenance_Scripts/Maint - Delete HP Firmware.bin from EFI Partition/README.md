<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Delete HP Firmware.bin from EFI Partition

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Delete_EFI_Firmware_BIN_File_DETECT.ps1

Mounts the EFI partition and looks for `K:\EFI\HP\DEVFW\firmware.bin`. Remediation is triggered only when the file is larger than 20 MB and has not been modified within the last 7 days, allowing time for a pending firmware update to apply after reboot. Output includes EFI free space. Exits **1** when criteria are met; **0** otherwise.

## PS_Delete_EFI_Firmware_BIN_File_REMEDIATE.ps1

Deletes the HP `firmware.bin` update file from the EFI partition when the detect script has flagged it. Frees space on EFI volumes where HP leaves a large post-update firmware payload behind.

Intended for HP devices where the stale firmware.bin file is safe to remove per the detect script's age and size rules.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

