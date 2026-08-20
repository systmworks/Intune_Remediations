<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Intune Remediations

A collection of Intune Remediation scripts that I have found particularly useful.

Each script folder contains a `README.md` with detect/remediate details. Deploy as **Intune Proactive Remediation** pairs (detect + remediate), running as **SYSTEM** unless noted otherwise.

## Maintenance Scripts

| Script folder | Description |
|---|---|
| [Maint - Clean Up Memory Dump Files](Maintenance_Scripts/Maint%20-%20Clean%20Up%20Memory%20Dump%20Files/) | Removes system and user crash dump files older than 7 days. |
| [Maint - Delete Fonts from EFI Partition](Maintenance_Scripts/Maint%20-%20Delete%20Fonts%20from%20EFI%20Partition/) | Deletes font files from the EFI partition to reclaim ~17 MB. |
| [Maint - Delete HP Firmware.bin from EFI Partition](Maintenance_Scripts/Maint%20-%20Delete%20HP%20Firmware.bin%20from%20EFI%20Partition/) | Deletes the HP firmware.bin update file from the EFI partition. |
| [Maint - Delete_OST_Files_Older_30_Days](Maintenance_Scripts/Maint%20-%20Delete_OST_Files_Older_30_Days/) | Removes Outlook OST files not modified in over 30 days. |
| [Maint - Enable Auto Update in Adobe Creative Cloud](Maintenance_Scripts/Maint%20-%20Enable%20Auto%20Update%20in%20Adobe%20Creative%20Cloud/) | Enables Creative Cloud Desktop and managed app auto-update settings. |
| [Maint - Extend C Partition to Max Size](Maintenance_Scripts/Maint%20-%20Extend%20C%20Partition%20to%20Max%20Size/) | Removes a blocking partition after C: (if safe) and extends C: into unallocated space. |
| [Maint - Remove Outdated .NET Runtimes](Maintenance_Scripts/Maint%20-%20Remove%20Outdated%20.NET%20Runtimes/) | Removes EOL or outdated .NET Runtime and Windows Desktop Runtime (dependency order enforced). |
| [Maint - Remove Outdated ASP.NET Runtimes (v1-v10)](Maintenance_Scripts/Maint%20-%20Remove%20Outdated%20ASP.NET%20Runtimes%20(v1-v10)/) | Uninstalls EOL ASP.NET Core runtimes via msiexec; removes outdated v8/v9/v10 only when a supported version remains. |
| [Maint - Remove Unwanted Store Apps](Maintenance_Scripts/Maint%20-%20Remove%20Unwanted%20Store%20Apps/) | Removes unwanted Microsoft Store apps from a configured blocklist. |

## Security Scripts

| Script folder | Description |
|---|---|
| [Security - Enable_Certificate_Padding_Check](Security_Scripts/Security%20-%20Enable_Certificate_Padding_Check/) | Sets EnableCertPaddingCheck registry values for Wintrust (native and Wow6432Node). |
| [Security - Enforce_TLS_1.3_Forward_Secrecy (Win11 Only)](Security_Scripts/Security%20-%20Enforce_TLS_1.3_Forward_Secrecy%20(Win11%20Only)/) | Hardens TLS/SCHANNEL settings on Windows 11; backs up registry to .reg before applying. |
| [Security - Fix_Unquoted_Paths in Registry](Security_Scripts/Security%20-%20Fix_Unquoted_Paths%20in%20Registry/) | Quotes unquoted ImagePath and UninstallString values in Services and Uninstall registry keys. |
| [Security - Speculative Execution Dynamic Mitigation](Security_Scripts/Security%20-%20Speculative%20Execution%20Dynamic%20Mitigation/) | Sets or removes FeatureSettingsOverride registry values to match hardware-optimal mitigation levels. |

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.