<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Remove Unwanted Store Apps

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Remove_Unwanted_Store_Apps_DETECT_1.7.ps1

Checks whether any apps from a configured blocklist are installed or provisioned on the device. The list includes consumer/bloat Store apps (Copilot, Dev Home, games, media apps, and similar). Exits **1** when one or more unwanted apps are found and lists them in output; **0** when none match.

Detection covers both installed packages and provisioned packages for new users.

## PS_Remove_Unwanted_Store_Apps_REMEDIATE_1.7.ps1

Attempts to remove unwanted Microsoft Store apps identified by the detect script's blocklist. Targets apps that should not be deployed in the managed environment.

Deploy as the remediation step in Intune after the detect script reports non-compliance. Review the blocklist before rollout to avoid removing apps your users need.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

