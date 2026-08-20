<########################################################
    Name:       PS_TLS_1.3_Forward_Secrecy_DETECT_v4.4.ps1
    Purpose:    Detects regkeys to ensure the values match those set by the companion Remediate script.
    Location:   Intune
    Owner:      Darren Milne
    Comments:   This script only checks the regkeys - it does NOT make any changes.
                Companion to script based on this:  https://www.hass.de/content/setup-microsoft-windows-or-iis-ssl-perfect-forward-secrecy-and-tls-12
                Windows 11 only. Includes per-user checks (online + offline hives).

    STRUCTURE:
        1) OS guard
        2) $keys check list (mirrors REMEDIATE config — source of truth is REMEDIATE script)
        3) Machine-wide check loop
        4) Per-user SecureProtocols (online + offline hives)
        5) Exit

    CHANGELOG:  (dd/mm/yyyy)

        17/04/2025 - v4.1 - New version to support Windows 11 and TLS 1.3
        22/04/2025 - v4.2 - Removed 2 ciphers that Rapid7 flag as insecure
        14/07/2026 - v4.3 - Added Windows 10 20H2+ support; online + offline per-user SecureProtocols check
        27/07/2026 - v4.4 - Windows 11 only. Detection aligned to REMEDIATE v4.4 settings
        28/07/2026 - v4.4 - OS guard, catch exit code, Wow6432Node checks, -LiteralPath reads
        28/07/2026 - v4.4 - Maintainability: mirror comments, restored inline documentation

########################################################>

$MinWindows11Build = [System.Version]'10.0.22000'

function Test-Windows11Requirement {
    param($OperatingSystem)

    if ([System.Version]$OperatingSystem.Version -lt $MinWindows11Build) {
        Write-Host "SKIPPED: This script requires Windows 11 (build $($MinWindows11Build)+). Detected build $($OperatingSystem.Version)."
        return $false
    }
    return $true
}

Start-Transcript -Path 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_TLS_1.3_Forward_Secrecy_DETECT_v4.4.log'

$os = Get-CimInstance -Class Win32_OperatingSystem
if (-not (Test-Windows11Requirement -OperatingSystem $os)) {
    Stop-Transcript | Out-Null
    exit 0
}

$cipherSuitesString = 'TLS_AES_256_GCM_SHA384,TLS_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA'

# Source of truth in hex (Microsoft's documented "enable all" DWORD for these SCHANNEL
# keys). Derived to decimal here rather than compared as hex directly — testing confirmed
# $Value -eq '0xFFFFFFFF' silently returns False against the UInt32 registry value.
$allEnabledHex = '0xFFFFFFFF'
$allEnabled = ([uint32]$allEnabledHex).ToString()

# --- CHECK LIST: mirrors REMEDIATE config (source of truth) ---
# Update this $keys array whenever REMEDIATE settings change.
# Order follows REMEDIATE: protocols, ciphers, hashes, KEA, .NET, WinHTTP, IE, cipher suites.
$keys = @(
# Disable Multi-Protocol Unified Hello
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Server'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Server'
        keyName='DisabledByDefault'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Client'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\Multi-Protocol Unified Hello\Client'
        keyName='DisabledByDefault'
        keyValue='1'
    },

# Disable PCT 1.0
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Server'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Server'
        keyName='DisabledByDefault'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Client'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\PCT 1.0\Client'
        keyName='DisabledByDefault'
        keyValue='1'
    },

# Disable SSL 2.0 (PCI Compliance)
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server'
        keyName='DisabledByDefault'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client'
        keyName='DisabledByDefault'
        keyValue='1'
    },

# Disable SSL 3.0 (PCI Compliance) and enable "Poodle" protection
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server'
        keyName='DisabledByDefault'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client'
        keyName='DisabledByDefault'
        keyValue='1'
    },

# Disable TLS 1.0 for client and server SCHANNEL communications
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'
        keyName='DisabledByDefault'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'
        keyName='DisabledByDefault'
        keyValue='1'
    },

# Add and Disable TLS 1.1 for client and server SCHANNEL communications
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'
        keyName='DisabledByDefault'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'
        keyName='DisabledByDefault'
        keyValue='1'
    },

# Add and Enable TLS 1.2 for client and server SCHANNEL communications
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'
        keyName='Enabled'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'
        keyName='DisabledByDefault'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
        keyName='Enabled'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'
        keyName='DisabledByDefault'
        keyValue='0'
    },

# Enable TLS 1.3 for client and server SCHANNEL communications (Windows 11)
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server'
        keyName='Enabled'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server'
        keyName='DisabledByDefault'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client'
        keyName='Enabled'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client'
        keyName='DisabledByDefault'
        keyValue='0'
    },

# Disable insecure/weak ciphers
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\DES 56/56'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\NULL'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 128/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 40/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 56/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 40/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 56/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 64/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 128/128'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168'
        keyName='Enabled'
        keyValue='0'
    },

# Enable new secure ciphers
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\AES 128/128'
        keyName='Enabled'
        keyValue=$allEnabled
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\AES 256/256'
        keyName='Enabled'
        keyValue=$allEnabled
    },

# Set hashes configuration
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\MD5'
        keyName='Enabled'
        keyValue='0'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\SHA'
        keyName='Enabled'
        keyValue=$allEnabled
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\SHA256'
        keyName='Enabled'
        keyValue=$allEnabled
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\SHA384'
        keyName='Enabled'
        keyValue=$allEnabled
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes\SHA512'
        keyName='Enabled'
        keyValue=$allEnabled
    },

# Set KeyExchangeAlgorithms configuration
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman'
        keyName='Enabled'
        keyValue=$allEnabled
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\ECDH'
        keyName='Enabled'
        keyValue=$allEnabled
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\PKCS'
        keyName='Enabled'
        keyValue=$allEnabled
    },

# Microsoft Security Advisory 3174644 - Updated Support for Diffie-Hellman Key Exchange
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman'
        keyName='ServerMinKeyBitLength'
        keyValue='2048'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\Diffie-Hellman'
        keyName='ClientMinKeyBitLength'
        keyValue='2048'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms\PKCS'
        keyName='ClientMinKeyBitLength'
        keyValue='2048'
    },

# Enable TLS 1.2 for .NET 3.5 and .NET 4.x
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'
        keyName='SystemDefaultTlsVersions'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'
        keyName='SchUseStrongCrypto'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
        keyName='SystemDefaultTlsVersions'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
        keyName='SchUseStrongCrypto'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727'
        keyName='SystemDefaultTlsVersions'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727'
        keyName='SchUseStrongCrypto'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'
        keyName='SystemDefaultTlsVersions'
        keyValue='1'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'
        keyName='SchUseStrongCrypto'
        keyValue='1'
    },

# Enable TLS 1.2 and TLS 1.3 as default secure protocols in WinHTTP
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
        keyName='DefaultSecureProtocols'
        keyValue='10240'
    },
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
        keyName='DefaultSecureProtocols'
        keyValue='10240'
    },

# Windows Internet Explorer: Activate TLS 1.2 and TLS 1.3 (machine-wide default).
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'
        keyName='SecureProtocols'
        keyValue='10240'
    },

# Set cipher suites order as secure as possible (Enables Perfect Forward Secrecy).
    [pscustomobject]@{
        keyPath='HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'
        keyName='Functions'
        keyValue=$cipherSuitesString
    }
)

# --- Helpers ---

Function Test-ValueExists {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path
    ,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Value
    )

    $regKey = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $regKey) {
        return $false
    }

    return ($regKey.GetValueNames() -contains $Value)
}

# --- Machine-wide registry check loop ---

$totalKeys = $keys.Count
$keyCount = 0

try {
    foreach ($key in $keys) {
        $Value = ''

        If (Test-ValueExists -Path $key.KeyPath -Value $key.keyName) {
            $Value = Get-ItemPropertyValue -LiteralPath $key.keyPath -Name $key.keyName

            If ($Value -eq $key.keyValue) {
                # value correct
            } Else {
                Write-Output "Incorrect value:  $($key.keyPath) \ $($key.keyName) = $($Value)"
                $keyCount++
            }
        } Else {
            Write-Output "Missing value:    $($key.keyPath) \ $($key.keyName)"
            $keyCount++
        }
    }

    # --- Per-user SecureProtocols (online + offline hives) ---
    # Counts as one logical check in $totalKeys/$keyCount (aggregate tally, not per-profile).

    $perUserCompliant = $true
    $excludedSIDs = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

    # HKEY_USERS only contains hives for logged-on accounts; _Classes/.DEFAULT are filtered out.
    $onlineUsers = Get-ChildItem 'Registry::HKEY_USERS' | Where-Object {
        $_.Name -notmatch '_Classes$' -and
        $_.PSChildName -ne '.DEFAULT' -and
        ($excludedSIDs -notcontains $_.PSChildName)
    }

    foreach ($user in $onlineUsers) {
        $userKeyPath = "Registry::HKEY_USERS\$($user.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
        if (Test-ValueExists -Path $userKeyPath -Value 'SecureProtocols') {
            $Value = Get-ItemPropertyValue -LiteralPath $userKeyPath -Name 'SecureProtocols'
            if ($Value -ne '10240') {
                Write-Output "Incorrect value:  $userKeyPath \ SecureProtocols = $Value (User $($user.PSChildName))"
                $perUserCompliant = $false
            }
        } else {
            Write-Output "Missing value:    $userKeyPath \ SecureProtocols (User $($user.PSChildName))"
            $perUserCompliant = $false
        }
    }

    $loggedOnSIDs = $onlineUsers.PSChildName
    $profileDirs = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('Default', 'Default User', 'Public', 'All Users')
    }

    $profileSidLookup = @{}
    try {
        Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | ForEach-Object {
            $profileSidLookup[$_.LocalPath] = $_.SID
        }
    } catch {
        Write-Output "WARN: Could not query Win32_UserProfile ($_) - offline profile matching skipped."
    }

    foreach ($profile in $profileDirs) {
        $ntUserPath = Join-Path $profile.FullName 'NTUSER.DAT'
        if (Test-Path $ntUserPath) {
            $sid = $profileSidLookup[$profile.FullName]
            if ($sid -and ($loggedOnSIDs -contains $sid)) {
                continue
            }

            # reg.exe is the only supported way to load/unload an offline NTUSER.DAT on PowerShell 5.1.
            $tempHive = "HKU\TempHive_$($profile.Name)"
            $hiveLoaded = $false
            try {
                # reg.exe does not throw on failure — check $LASTEXITCODE, not try/catch alone.
                reg load $tempHive $ntUserPath 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $hiveLoaded = $true
                    $offlineKeyPath = "Registry::$tempHive\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
                    if (Test-ValueExists -Path $offlineKeyPath -Value 'SecureProtocols') {
                        $Value = Get-ItemPropertyValue -LiteralPath $offlineKeyPath -Name 'SecureProtocols'
                        if ($Value -ne '10240') {
                            Write-Output "Incorrect value:  $offlineKeyPath \ SecureProtocols = $Value (Offline User $($profile.Name))"
                            $perUserCompliant = $false
                        }
                    } else {
                        Write-Output "Missing value:    $offlineKeyPath \ SecureProtocols (Offline User $($profile.Name))"
                        $perUserCompliant = $false
                    }
                } else {
                    Write-Output "FAILED: Could not load hive for $($profile.Name) (reg load exit code $LASTEXITCODE)"
                    $perUserCompliant = $false
                }
            } catch {
                Write-Output "FAILED: Could not load hive for $($profile.Name) ($_)"
                $perUserCompliant = $false
            } finally {
                if ($hiveLoaded) {
                    # Force GC first — a lingering .NET registry handle can keep the hive locked on unload.
                    [gc]::Collect()
                    [gc]::WaitForPendingFinalizers()
                    reg unload $tempHive 2>&1 | Out-Null
                }
            }
        }
    }

    $totalKeys++
    if (-not $perUserCompliant) {
        $keyCount++
    }

    If ($keyCount -eq 0) {
        Write-Host "All $totalKeys keys present and correct :)" -ForegroundColor Green
        Stop-Transcript | Out-Null
        Exit 0
    } Else {
        Write-Host "$keyCount of $totalKeys keys missing or incorrect :(" -ForegroundColor Red
        Stop-Transcript | Out-Null
        Exit 1
    }
} catch {
    Write-Error $_.Exception.Message
    Stop-Transcript | Out-Null
    exit 1
}
