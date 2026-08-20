# v4.4 Supporting Documentation

**Supporting documentation only.** The scripts (`PS_TLS_1.3_Forward_Secrecy_*.ps1`) are the
canonical source for settings, structure, and inline reasoning. **REMEDIATE is the source of
truth for registry settings; DETECT mirrors it.** This file may duplicate script comments but
must not replace them.

This file is a record of *why* the code looks the way it does, not a to-do list.

---

## Design principles

Recorded here so they survive the next rewrite. These are the rules that should shape any future version.

- **Don't overcomplicate — simple is almost always better.** Prefer deleting code over fixing it,
  and prefer a plain built-in mechanism over a bespoke one. Every abstraction has to earn its
  place; if a wrapper, helper or data structure isn't paying for itself, remove it. When a fix and
  a deletion would both solve the problem, take the deletion.
- **`DETECT` is the compliance authority; `REMEDIATE` is a dumb brute-force apply.** Intune re-runs
  the detection script immediately after the remediation script, so `DETECT` decides the true state
  of the device. `REMEDIATE` doesn't need to grade its own work — it doesn't need per-step error
  tracking, exit-code aggregation, or conditional logic that tries to predict what `DETECT` will
  find. Keep the checks thorough and unconditional in `DETECT`, and keep `REMEDIATE` linear.
- **Keep one source of truth.** REMEDIATE config section owns the registry settings list.
  DETECT mirrors it with sync comments. Backup derives from the same REMEDIATE config arrays —
  no third hand-maintained copy.

---

## Registry path rules

Lessons from production debugging — apply to any future registry work in these scripts.

- **Never use `Join-Path` to build a registry path from a segment that might contain `/`.**
  Registry key names can contain `/` legally (several default Windows SCHANNEL cipher names do,
  e.g. `AES 128/128`); `Join-Path` silently normalizes `/` to `\`, pointing at the wrong key.
  Use plain string concatenation (`"$parent\$child"`) instead.
- **Cipher subkeys with `/` in the name must use `.CreateSubKey()`**, not `New-Item -Path`.
  `New-Item -Path '...\AES 128/128'` creates nested `AES 128\128`, not a single slash-named key.
- **Never use `Group-Object -Property SomeKey` on an array of hashtables** — it looks for note
  properties, not keys. Use `Group-Object { $_.SomeKey }` instead.
- **`-LiteralPath` and hardcoded literal paths** (as in DETECT and REMEDIATE apply) do not exhibit
  slash normalization — only path-building via `Join-Path` is unsafe here.

---

## Backup and rollback (.reg)

`REMEDIATE` writes one composed `.reg` file per run **before** making changes. The backup captures
live pre-remediation state; `ROLLBACK` restores that, not the hardened targets.

**Backup composition:**

1. Header (`Windows Registry Editor Version 5.00`)
2. **Targeted delete directives first** — `[-Key]` only for keys absent at backup time; `"Name"=-`
   only for values absent on keys that do exist. Never a blanket subtree delete.
3. **`reg export`** of `HKLM\...\SCHANNEL` if present (captures slash-containing cipher names correctly)
4. **`reg export`** of `HKLM\...\SSL\00010002` if present
5. **Hand-built DWORD sections** for the 11 non-SCHANNEL values (parent keys hold unrelated Windows
   config and must never be deleted wholesale)

**ROLLBACK:** select earliest `.reg` by filename timestamp, `reg import`, check `$LASTEXITCODE`.
Machine-wide keys only; per-user `SecureProtocols` is out of scope. Reboot required for SCHANNEL
changes to fully take effect.

**Verified locally (28/07/2026, HKCU scratch keys + V-PRD700 production):**

| Test | Result |
|------|--------|
| `reg export` / `reg import` round-trip of key named `AES 128/128` | Pass — literal `/` preserved |
| Sequential `[-Key]` then `[Key]` with value in one file | Pass — key recreated, extra values gone |
| `[-Key]` for a key that does not exist | Pass — `reg import` exit 0 |
| File composed in PowerShell with `-Encoding Unicode` (UTF-16 LE) | Pass — imports cleanly |
| `New-Item -Force` on an existing key with extra values | **Wipes all values** — confirms SCHANNEL `reg export` is load-bearing |
| Pre-remediation DWORD values captured (e.g. `SecureProtocols=8`) | Pass on V-PRD700 |

---

## Technical reference

### Why `$allEnabled` is derived to decimal in DETECT

Microsoft's documented "enable all" DWORD is `0xFFFFFFFF`. In DETECT, comparing directly fails:

```powershell
$Value -eq '0xFFFFFFFF'   # silently returns False against the UInt32 registry value
```

So DETECT derives: `$allEnabled = ([uint32]'0xFFFFFFFF').ToString()` → `'4294967295'`.

### DefaultSecureProtocols bitmask

Used for machine-wide and per-user `SecureProtocols` / `DefaultSecureProtocols` (value `10240`):

| Protocol | Bit value |
|----------|-----------|
| SSL 2.0 | 8 |
| SSL 3.0 | 32 |
| TLS 1.0 | 128 |
| TLS 1.1 | 512 |
| TLS 1.2 | 2048 |
| TLS 1.3 | 8192 |

TLS 1.2 + TLS 1.3 = 2048 + 8192 = **10240**.

### Per-user hive handling (online + offline)

- **`reg.exe` is required** on PowerShell 5.1 — there is no native cmdlet to load/unload an offline
  `NTUSER.DAT`.
- **`reg.exe` does not throw** on failure — success/failure must be checked via `$LASTEXITCODE`, not
  `try/catch`.
- **`[gc]::Collect()` before `reg unload`** — a lingering .NET registry handle from
  `Get-ItemPropertyValue` can keep the hive file locked and cause unload to fail with the hive left
  mounted.
- **CIM query hoisted out of the loop** — one `Win32_UserProfile` query builds a path→SID lookup
  table instead of a WMI round-trip per profile folder.
- **Single aggregate tally in DETECT** — the per-user section counts as one logical check so
  `$totalKeys`/`$keyCount` don't scale with however many profiles exist on a device.

### Hass operational notes (from original REMEDIATE)

- **SSL 3.0 disable** may lock out legacy WinXP/IE6-7 clients with no fallback protocol.
- **`Triple DES 168`** was named `Triple DES 168/168` pre-Vista (KB245030).
- **`00010002` cipher suite key** reportedly missing on Windows 2012R2 on some machines; REMEDIATE
  uses `New-Item -Force` to create the parent chain.
- **WinHttp Wow6432Node key** reportedly missing on Windows 2019; REMEDIATE creates it if absent.
- Reference links from the original script:
  - [Microsoft Security Advisory 3174644](https://docs.microsoft.com/en-us/security-updates/SecurityAdvisories/2016/3174644)
  - [KB3140245 — enable TLS 1.1/1.2 as default secure protocols in WinHTTP](https://support.microsoft.com/en-us/help/3140245/update-to-enable-tls-1-1-and-tls-1-2-as-a-default-secure-protocols-in)
  - [Exchange Server TLS guidance](https://blogs.technet.microsoft.com/exchange/2018/04/02/exchange-server-tls-guidance-part-2-enabling-tls-1-2-and-identifying-clients-not-using-it/)

### Windows 11 only — Intune assignment

v4.4 removed Windows 10 20H2+ support. Both DETECT and REMEDIATE exit **0** (not applicable) on
non-Win11 builds, but the Intune assignment should still carry a **Windows 11 filter** so unsupported
devices are never evaluated.

---

# Production issues and fixes

Issues found during test-device debugging on 28/07/2026. Historical context for the current `.reg`
backup implementation.

---

## Bug: Backup crashed with empty LiteralPath in Export-TlsRegistryBackup

**Symptom** (from Intune transcript):

```
PS>TerminatingError(Test-Path): "Cannot bind argument to parameter 'LiteralPath' because it is an empty string."
>> TerminatingError(Export-TlsRegistryBackup): "Cannot bind argument to parameter 'LiteralPath' because it is an empty string."
FAILED: Could not write registry backup (Cannot bind argument to parameter 'LiteralPath' because it is an empty string.)
```

**Root cause:** `$nonSchannelDwordTargets` is an array of **hashtables** (`@{ Path = '...'; Name = '...' }`).
`Group-Object -Property Path` does not read hashtable keys — it looks for note properties, so every
group's `.Name` was empty. The next line called `Test-Path -LiteralPath ''`, which throws.

**Fix:** use script-block grouping so the Path key is read explicitly:

```powershell
foreach ($group in ($nonSchannelDwordTargets | Group-Object { $_.Path })) {
```

**Verified on V-PRD700 (Win11, 28/07/2026):** after this fix, REMEDIATE completed backup and
full remediation successfully. Backup file `TLS_1.3_Forward_Secrecy_Backup_V-PRD700_20260728_032911.reg`
written with correct pre-remediation DWORD values (including `SecureProtocols=8` test case).
