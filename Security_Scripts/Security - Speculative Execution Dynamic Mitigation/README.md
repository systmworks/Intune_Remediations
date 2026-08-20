<p align="center"><a href="https://buymeacoffee.com/systmworks"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="45" alt="Buy me a coffee"></a></p>
# Speculative Execution Dynamic Mitigation

Intune Proactive Remediation scripts in this folder. Run as **SYSTEM**.

## PS_Speculative_Execution_Vulnerability_DETECT.ps1

Assesses whether `FeatureSettingsOverride` and `FeatureSettingsOverrideMask` registry values are forcing unnecessary CPU speculation mitigations on hardware that is immune to those vulnerabilities. Calculates the optimal override for the specific CPU (Intel model database, AMD handling, kernel KVA/Meltdown hints) and compares against current settings. Exits **0** when compliant; **1** when overrides can be safely reduced.

Standalone — no PowerShell modules required. Detailed logs are written to `C:\ProgramData\SpecControlAssessment\`. A single summary line is suitable for Intune CSV collection.

## PS_Speculative_Execution_Vulnerability_REMEDIATE.ps1

Sets or removes `FeatureSettingsOverride` and `FeatureSettingsOverrideMask` to match the detect script's optimal values for the device. Uses the same Intel model database, CPU identification, and override rules as detect. When optimal state is to remove the keys, both DWORDs are deleted; otherwise they are set to the calculated values with mask `0x3`.

Runs silently with no log files unless debug mode is enabled (`$script:RemediationDebug` or `SPEC_CONTROL_REMEDIATE_DEBUG=1`). A reboot may be required for mitigation state to fully settle.

**Sharing & responsibility** - Built for the community, shared with good intentions. Use at your own risk. The author accepts no responsibility for any outcomes resulting from the use of these files. Always verify registry paths and values, and test in a safe environment first. If you find an issue or have a suggestion, contributions are welcome.