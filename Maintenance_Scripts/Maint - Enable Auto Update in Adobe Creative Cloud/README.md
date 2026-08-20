<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Enable Auto Update in Adobe Creative Cloud

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Adobe_CC_Auto_Updates_DETECT.ps1

Checks Creative Cloud Desktop and managed Adobe app auto-update preferences under each user's `AppData\Local\Adobe\OOBE` profile data. Enumerates profiles via `Win32_UserProfile` because the script runs as SYSTEM. Exits **0** when compliant or when issues are classified as review-only (no remediation loop); exits **1** when fixable non-compliance is found.

Acrobat and Reader are out of scope (updated by Patch My PC). Changes may not apply until Creative Cloud next launches.

## PS_Adobe_CC_Auto_Updates_REMEDIATE.ps1

Enables Creative Cloud Desktop and CC managed app auto-update settings to match the detect script's expected configuration. Applies per-user preference fixes across discovered profiles.

Pair with the detect script in Intune proactive remediation. Classification logic should stay in sync between both files when prefs rules change.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

