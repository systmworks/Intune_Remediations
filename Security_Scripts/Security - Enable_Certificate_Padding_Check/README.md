<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Enable Certificate Padding Check

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Cert_Padding_DETECT.ps1

Verifies that `EnableCertPaddingCheck` is set to `1` in both `HKLM\Software\Microsoft\Cryptography\Wintrust\Config` and the Wow6432Node equivalent. This registry setting helps mitigate certificate padding oracle attacks. Exits **0** when both keys exist and are correct; **1** when any are missing or wrong.

This script only checks registry values — it does not make changes.

## PS_Cert_Padding_REMEDIATE.ps1

Creates the Wintrust Config keys if needed and sets `EnableCertPaddingCheck` to `1` for both native and Wow6432Node paths. Applies the Microsoft-recommended certificate padding check hardening.

Deploy as the remediation step after the detect script reports non-compliance.

---

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

