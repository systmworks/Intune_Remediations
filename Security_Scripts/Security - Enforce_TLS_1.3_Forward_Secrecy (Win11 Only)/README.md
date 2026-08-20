<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>

# Enforce TLS 1.3 and Forward Secrecy (Windows 11 Only)

Intune Proactive Remediation scripts in this folder. **Windows 11 only.** Run as **SYSTEM** for detect/remediate; rollback is manual admin use.

Based on Alexander Hass's TLS hardening guidance. See [SUPPORTING_DOCUMENTATION.md](SUPPORTING_DOCUMENTATION.md) for additional detail.

## PS_TLS_1.3_Forward_Secrecy_DETECT_v4.4.ps1

Compares machine-wide and per-user TLS/SCHANNEL registry values against the settings applied by the remediate script. Checks protocols, ciphers, hashes, key exchange algorithms, cipher suites, .NET SchUseStrongCrypto, WinHTTP, and IE/Edge SecureProtocols (online and offline user hives). Exits **0** when compliant; **1** when drift is detected.

Does not modify registry values. Detection mirrors the remediate script's config as the source of truth.

## PS_TLS_1.3_Forward_Secrecy_REMEDIATE_v4.4.ps1

Hardens TLS/SCHANNEL settings on Windows 11 for perfect forward secrecy and TLS 1.3 support. Exports a timestamped `.reg` backup of machine-wide settings before applying changes, enabling rollback. Applies settings in Hass order (protocols, ciphers, hashes, KEA, cipher suites, .NET, WinHTTP, IE) and enforces per-user SecureProtocols for online and offline hives.

Requires Windows 11. A reboot may be needed for SCHANNEL changes to fully take effect.

## PS_TLS_1.3_Forward_Secrecy_ROLLBACK_v4.4.ps1

Restores machine-wide TLS/SCHANNEL registry settings from a `.reg` backup created by the remediate script. Run manually by an administrator when rollback is needed — not intended for Intune scheduled deployment. By default selects the earliest backup on the device (true pre-remediation state). Per-user SecureProtocols is out of scope for rollback.

A reboot is required for SCHANNEL changes to fully take effect after import.

---

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.

