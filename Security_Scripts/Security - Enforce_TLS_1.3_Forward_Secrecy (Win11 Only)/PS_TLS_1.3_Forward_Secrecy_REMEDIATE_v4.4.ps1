<########################################################
    Name:       PS_TLS_1.3_Forward_Secrecy_REMEDIATE_v4.4.ps1
    Purpose:    Remediates TLS/SCHANNEL settings for Windows 11; backs up machine-wide
                registry state to a timestamped .reg file before applying changes.
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Most of this script was created by Alexander Hass
                https://www.hass.de/content/setup-microsoft-windows-or-iis-ssl-perfect-forward-secrecy-and-tls-12
                Includes per-user TLS enforcement (online + offline hives).
                Windows 11 only. Machine-wide backup supports companion ROLLBACK script.

    STRUCTURE:
        1) Config (source of truth for registry settings — update DETECT when changed)
        2) Backup helpers
        3) OS guard, transcript, backup export
        4) Apply (Hass order: protocols, ciphers, hashes, KEA, cipher suites, .NET, WinHTTP, IE)
        5) Per-user SecureProtocols (online + offline hives)
        6) Exit

    CHANGELOG:  (dd/mm/yyyy)

        17/04/2025 - v4.1 - Updated script based on v4.0.1 from Alexander Hass to support Win11 and TLS 1.3
        22/04/2025 - v4.2 - Removed 2 ciphers that Rapid7 flag as insecure
        14/07/2026 - v4.3 - Merged per-user SecureProtocols enforcement (online + offline hives)
        27/07/2026 - v4.4 - Windows 11 only. Pre-remediation .reg backup + companion ROLLBACK script
        28/07/2026 - v4.4 - Simplified backup (reg export + targeted deletes), linear apply, protocol table.
                             Bugfixes documented in KNOWN_ISSUES_AND_FIXES.md (supporting reference)
        28/07/2026 - v4.4 - Maintainability: config section labelled source of truth; backup derives
                             from config arrays; restored inline documentation

########################################################>

$ScriptVersion = '4.4'
$MinWindows11Build = [System.Version]'10.0.22000'
$BackupFolder = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\TLS_1.3_Backups'
$LogPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_TLS_1.3_Forward_Secrecy_REMEDIATE_v4.4.log'

# --- SOURCE OF TRUTH: registry settings (Hass order) ---
# When changing settings here, update the DETECT script $keys array to mirror.
# Intune uploads this script body only — no companion data files on the endpoint.

$SchannelBase = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'
$CipherSuitesKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'
$SchannelRegExportPath = 'HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL'
$CipherSuitesRegExportPath = 'HKLM\SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'

# Protocol Enabled values (0 = disabled, 1 = enabled). DisabledByDefault is the inverse.
$protocolState = [ordered]@{
    'Multi-Protocol Unified Hello' = 0
    'PCT 1.0'                      = 0
    'SSL 2.0'                      = 0
    'SSL 3.0'                      = 0
    'TLS 1.0'                      = 0
    'TLS 1.1'                      = 0
    'TLS 1.2'                      = 1
    'TLS 1.3'                      = 1
}

$insecureCiphers = @(
    'DES 56/56',
    'NULL',
    'RC2 128/128',
    'RC2 40/128',
    'RC2 56/128',
    'RC4 40/128',
    'RC4 56/128',
    'RC4 64/128',
    'RC4 128/128',
    'Triple DES 168'
)

$secureCiphers = @(
    'AES 128/128',
    'AES 256/256'
)

$secureHashes = @(
    'SHA',
    'SHA256',
    'SHA384',
    'SHA512'
)

$secureKeyExchangeAlgorithms = @(
    'Diffie-Hellman',
    'ECDH',
    'PKCS'
)

$cipherSuitesOrder = @(
    'TLS_AES_256_GCM_SHA384',
    'TLS_AES_128_GCM_SHA256',
    'TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384',
    'TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256',
    'TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384',
    'TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256',
    'TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384',
    'TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256',
    'TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384',
    'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256',
    'TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA',
    'TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA'
)
$cipherSuitesString = [string]::Join(',', $cipherSuitesOrder)

# DefaultSecureProtocols bitmask (additive): SSL2=8, SSL3=32, TLS1.0=128, TLS1.1=512,
# TLS1.2=2048, TLS1.3=8192. e.g. TLS1.2+TLS1.3 = 2048+8192 = 10240.
$defaultSecureProtocols = @(
    '2048',  # TLS 1.2
    '8192'   # TLS 1.3
)
$defaultSecureProtocolsSum = ($defaultSecureProtocols | Measure-Object -Sum).Sum

# Non-SCHANNEL DWORD values only — parent keys hold unrelated Windows config and are never deleted wholesale.
$nonSchannelDwordTargets = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'; Name = 'SystemDefaultTlsVersions' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727'; Name = 'SchUseStrongCrypto' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'; Name = 'SystemDefaultTlsVersions' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319'; Name = 'SchUseStrongCrypto' },
    @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727'; Name = 'SystemDefaultTlsVersions' },
    @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727'; Name = 'SchUseStrongCrypto' },
    @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; Name = 'SystemDefaultTlsVersions' },
    @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319'; Name = 'SchUseStrongCrypto' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'; Name = 'DefaultSecureProtocols' },
    @{ Path = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'; Name = 'DefaultSecureProtocols' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings'; Name = 'SecureProtocols' }
)

# --- Backup helpers ---
# Captures live pre-remediation registry state; ROLLBACK restores this, not the hardened targets.

function ConvertTo-RegFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -like 'HKLM:\*') {
        return 'HKEY_LOCAL_MACHINE\' + $Path.Substring(6)
    }
    if ($Path -like 'HKCU:\*') {
        return 'HKEY_CURRENT_USER\' + $Path.Substring(6)
    }
    throw "Unsupported registry root in path: $Path"
}

function Get-RegValueState {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{
            KeyExisted   = $false
            ValueExisted = $false
            Value        = $null
        }
    }

    $regKey = Get-Item -LiteralPath $Path
    if ($regKey.GetValueNames() -contains $Name) {
        return @{
            KeyExisted   = $true
            ValueExisted = $true
            Value        = $regKey.GetValue($Name)
        }
    }

    return @{
        KeyExisted   = $true
        ValueExisted = $false
        Value        = $null
    }
}

function Format-RegDwordLine {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value
    )

    return '"{0}"=dword:{1:x8}' -f $Name, [uint32]$Value
}

function Get-RegExportBody {
    param([Parameter(Mandatory = $true)][string]$RegPath)

    $tempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName() + '.reg')
    try {
        reg export $RegPath $tempFile /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        $lines = [System.IO.File]::ReadAllLines($tempFile, [System.Text.Encoding]::Unicode)
        if ($lines.Count -le 2) {
            return $null
        }

        return (($lines | Select-Object -Skip 2) -join "`r`n").Trim()
    } finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Export-TlsRegistryBackup {
    param([Parameter(Mandatory = $true)][string]$BackupFilePath)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Windows Registry Editor Version 5.00')
    $lines.Add('')

    # Delete directives derived directly from config arrays (no separate target list).
    $keysToDelete = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $valueDeletes = New-Object System.Collections.Generic.List[object]

    foreach ($protocolName in $protocolState.Keys) {
        foreach ($role in @('Server', 'Client')) {
            $path = "$SchannelBase\Protocols\$protocolName\$role"
            foreach ($name in @('Enabled', 'DisabledByDefault')) {
                $state = Get-RegValueState -Path $path -Name $name
                if (-not $state.KeyExisted) {
                    [void]$keysToDelete.Add((ConvertTo-RegFilePath -Path $path))
                } elseif (-not $state.ValueExisted) {
                    $valueDeletes.Add(@{ RegPath = (ConvertTo-RegFilePath -Path $path); Name = $name })
                }
            }
        }
    }

    foreach ($cipher in ($insecureCiphers + $secureCiphers)) {
        $path = "$SchannelBase\Ciphers\$cipher"
        $state = Get-RegValueState -Path $path -Name 'Enabled'
        if (-not $state.KeyExisted) {
            [void]$keysToDelete.Add((ConvertTo-RegFilePath -Path $path))
        } elseif (-not $state.ValueExisted) {
            $valueDeletes.Add(@{ RegPath = (ConvertTo-RegFilePath -Path $path); Name = 'Enabled' })
        }
    }

    foreach ($hash in $secureHashes) {
        $path = "$SchannelBase\Hashes\$hash"
        $state = Get-RegValueState -Path $path -Name 'Enabled'
        if (-not $state.KeyExisted) {
            [void]$keysToDelete.Add((ConvertTo-RegFilePath -Path $path))
        } elseif (-not $state.ValueExisted) {
            $valueDeletes.Add(@{ RegPath = (ConvertTo-RegFilePath -Path $path); Name = 'Enabled' })
        }
    }

    $md5Path = "$SchannelBase\Hashes\MD5"
    $state = Get-RegValueState -Path $md5Path -Name 'Enabled'
    if (-not $state.KeyExisted) {
        [void]$keysToDelete.Add((ConvertTo-RegFilePath -Path $md5Path))
    } elseif (-not $state.ValueExisted) {
        $valueDeletes.Add(@{ RegPath = (ConvertTo-RegFilePath -Path $md5Path); Name = 'Enabled' })
    }

    foreach ($kea in $secureKeyExchangeAlgorithms) {
        $path = "$SchannelBase\KeyExchangeAlgorithms\$kea"
        $state = Get-RegValueState -Path $path -Name 'Enabled'
        if (-not $state.KeyExisted) {
            [void]$keysToDelete.Add((ConvertTo-RegFilePath -Path $path))
        } elseif (-not $state.ValueExisted) {
            $valueDeletes.Add(@{ RegPath = (ConvertTo-RegFilePath -Path $path); Name = 'Enabled' })
        }
    }

    foreach ($target in @(
        @{ Path = "$SchannelBase\KeyExchangeAlgorithms\Diffie-Hellman"; Name = 'ServerMinKeyBitLength' }
        @{ Path = "$SchannelBase\KeyExchangeAlgorithms\Diffie-Hellman"; Name = 'ClientMinKeyBitLength' }
        @{ Path = "$SchannelBase\KeyExchangeAlgorithms\PKCS"; Name = 'ClientMinKeyBitLength' }
        @{ Path = $CipherSuitesKey; Name = 'Functions' }
    ) + $nonSchannelDwordTargets) {
        $state = Get-RegValueState -Path $target.Path -Name $target.Name
        if (-not $state.KeyExisted) {
            [void]$keysToDelete.Add((ConvertTo-RegFilePath -Path $target.Path))
        } elseif (-not $state.ValueExisted) {
            $valueDeletes.Add(@{ RegPath = (ConvertTo-RegFilePath -Path $target.Path); Name = $target.Name })
        }
    }

    foreach ($regPath in $keysToDelete) {
        $lines.Add("[-$regPath]")
        $lines.Add('')
    }

    foreach ($delete in $valueDeletes) {
        $lines.Add("[$($delete.RegPath)]")
        $lines.Add('"'+$delete.Name+'"=-')
        $lines.Add('')
    }

    if (Test-Path -LiteralPath $SchannelBase) {
        $schannelBody = Get-RegExportBody -RegPath $SchannelRegExportPath
        if ($schannelBody) {
            $lines.Add($schannelBody)
            $lines.Add('')
        }
    }

    if (Test-Path -LiteralPath $CipherSuitesKey) {
        $cipherSuitesBody = Get-RegExportBody -RegPath $CipherSuitesRegExportPath
        if ($cipherSuitesBody) {
            $lines.Add($cipherSuitesBody)
            $lines.Add('')
        }
    }

    foreach ($group in ($nonSchannelDwordTargets | Group-Object { $_.Path })) {
        $path = $group.Name
        if ([string]::IsNullOrEmpty($path)) {
            continue
        }

        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        $regPath = ConvertTo-RegFilePath -Path $path
        $sectionLines = New-Object System.Collections.Generic.List[string]
        $sectionLines.Add("[$regPath]")

        foreach ($target in $group.Group) {
            $state = Get-RegValueState -Path $path -Name $target.Name
            if ($state.ValueExisted) {
                $sectionLines.Add((Format-RegDwordLine -Name $target.Name -Value $state.Value))
            }
        }

        if ($sectionLines.Count -gt 1) {
            $lines.Add(($sectionLines -join "`r`n"))
            $lines.Add('')
        }
    }

    $content = ($lines -join "`r`n").TrimEnd()
    [System.IO.File]::WriteAllText($BackupFilePath, $content, [System.Text.Encoding]::Unicode)
}

function Test-Windows11Requirement {
    param($OperatingSystem)

    if ([System.Version]$OperatingSystem.Version -lt $MinWindows11Build) {
        Write-Host "SKIPPED: This script requires Windows 11 (build $($MinWindows11Build)+). Detected build $($OperatingSystem.Version)."
        return $false
    }
    return $true
}

function Write-RemediateLog {
    param(
        [Parameter(Mandatory = $true)][string]$Item,
        [Parameter(Mandatory = $true)][string]$State,
        [Parameter(Mandatory = $true)][string]$RegistryDetail
    )

    $detailColumn = 50   # '(' starts at this 1-based column
    $left = "$Item $State"
    $padded = $left.PadRight($detailColumn - 1)
    Write-Host "$padded($RegistryDetail)"
}

# --- OS guard and transcript ---

Start-Transcript -Path $LogPath -Append
$date = Get-Date -Format 'dddd dd/MM/yyyy'
Write-Host '--------------------------------------------------------------------------------'
Write-Host "Starting Remediation Script v$ScriptVersion - ($date)"
Write-Host '--------------------------------------------------------------------------------'

$os = Get-CimInstance -Class Win32_OperatingSystem
if (-not (Test-Windows11Requirement -OperatingSystem $os)) {
    Stop-Transcript | Out-Null
    exit 0
}

# --- Pre-remediation backup ---

$computerName = $env:COMPUTERNAME
$backupTimestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')

Write-Host '--------------------------------------------------------------------------------'
Write-Host 'Backing up machine-wide registry state before remediation...'
Write-Host '--------------------------------------------------------------------------------'

if (-not (Test-Path -LiteralPath $BackupFolder)) {
    New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
}

$backupFileName = "TLS_1.3_Forward_Secrecy_Backup_${computerName}_${backupTimestamp}.reg"
$backupFilePath = Join-Path -Path $BackupFolder -ChildPath $backupFileName

try {
    Export-TlsRegistryBackup -BackupFilePath $backupFilePath
    Write-Host "Backup written: $backupFilePath"
} catch {
    Write-Host "FAILED: Could not write registry backup ($($_.Exception.Message))"
    Stop-Transcript | Out-Null
    exit 1
}

# --- Apply SCHANNEL settings (Hass order) ---

Write-Host 'Configuring IIS with SSL/TLS Deployment Best Practices...'
Write-Host '--------------------------------------------------------------------------------'

# NOTE: disabling SSL 3.0 (in $protocolState) may lock out legacy WinXP/IE6-7 clients with no fallback protocol.
foreach ($protocolName in $protocolState.Keys) {
    $enabled = [int]$protocolState[$protocolName]
    $disabledByDefault = if ($enabled -eq 1) { 0 } else { 1 }

    foreach ($role in @('Server', 'Client')) {
        $protocolPath = "$SchannelBase\Protocols\$protocolName\$role"
        New-Item -Path $protocolPath -Force | Out-Null
        New-ItemProperty -Path $protocolPath -Name Enabled -Value $enabled -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $protocolPath -Name DisabledByDefault -Value $disabledByDefault -PropertyType DWord -Force | Out-Null
    }

    $stateLabel = if ($enabled -eq 1) { 'Enabled' } else { 'Disabled' }
    Write-RemediateLog -Item "Protocol $protocolName" -State $stateLabel -RegistryDetail "Enabled=$enabled, DisabledByDefault=$disabledByDefault"
}

# Re-create the ciphers key.
New-Item "$SchannelBase\Ciphers" -Force | Out-Null

# Use .CreateSubKey() for cipher names — New-Item treats '/' as a path separator (see KNOWN_ISSUES_AND_FIXES.md).
Foreach ($insecureCipher in $insecureCiphers) {
    $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers', $true).CreateSubKey($insecureCipher)
    $key.SetValue('Enabled', 0, 'DWord')
    $key.Close()
    Write-RemediateLog -Item "Cipher $insecureCipher" -State 'Disabled' -RegistryDetail 'Enabled=0'
}

Foreach ($secureCipher in $secureCiphers) {
    $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers', $true).CreateSubKey($secureCipher)
    New-ItemProperty -Path "$SchannelBase\Ciphers\$secureCipher" -Name Enabled -Value '0xffffffff' -PropertyType DWord -Force | Out-Null
    $key.Close()
    Write-RemediateLog -Item "Cipher $secureCipher" -State 'Enabled' -RegistryDetail 'Enabled=0xffffffff'
}

New-Item "$SchannelBase\Hashes" -Force | Out-Null
New-Item "$SchannelBase\Hashes\MD5" -Force | Out-Null
New-ItemProperty -Path "$SchannelBase\Hashes\MD5" -Name Enabled -Value 0 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item 'Hash MD5' -State 'Disabled' -RegistryDetail 'Enabled=0'

Foreach ($secureHash in $secureHashes) {
    $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes', $true).CreateSubKey($secureHash)
    New-ItemProperty -Path "$SchannelBase\Hashes\$secureHash" -Name Enabled -Value '0xffffffff' -PropertyType DWord -Force | Out-Null
    $key.Close()
    Write-RemediateLog -Item "Hash $secureHash" -State 'Enabled' -RegistryDetail 'Enabled=0xffffffff'
}

New-Item "$SchannelBase\KeyExchangeAlgorithms" -Force | Out-Null
Foreach ($secureKeyExchangeAlgorithm in $secureKeyExchangeAlgorithms) {
    $key = (Get-Item HKLM:\).OpenSubKey('SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\KeyExchangeAlgorithms', $true).CreateSubKey($secureKeyExchangeAlgorithm)
    New-ItemProperty -Path "$SchannelBase\KeyExchangeAlgorithms\$secureKeyExchangeAlgorithm" -Name Enabled -Value '0xffffffff' -PropertyType DWord -Force | Out-Null
    $key.Close()
    Write-RemediateLog -Item "KeyExchangeAlgorithm $secureKeyExchangeAlgorithm" -State 'Enabled' -RegistryDetail 'Enabled=0xffffffff'
}

New-ItemProperty -Path "$SchannelBase\KeyExchangeAlgorithms\Diffie-Hellman" -Name ServerMinKeyBitLength -Value 2048 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path "$SchannelBase\KeyExchangeAlgorithms\Diffie-Hellman" -Name ClientMinKeyBitLength -Value 2048 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item 'KeyExchangeAlgorithm Diffie-Hellman' -State 'Enabled' -RegistryDetail 'ServerMinKeyBitLength=2048, ClientMinKeyBitLength=2048'

New-ItemProperty -Path "$SchannelBase\KeyExchangeAlgorithms\PKCS" -Name ClientMinKeyBitLength -Value 2048 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item 'KeyExchangeAlgorithm PKCS' -State 'Enabled' -RegistryDetail 'ClientMinKeyBitLength=2048'

# 00010002 key may be missing on some machines — New-Item -Force creates the parent chain.
New-Item -Path $CipherSuitesKey -Force | Out-Null
New-ItemProperty -Path $CipherSuitesKey -Name Functions -Value $cipherSuitesString -PropertyType String -Force | Out-Null
Write-RemediateLog -Item 'Cipher suites order' -State 'Enabled' -RegistryDetail "Functions=$cipherSuitesString"

New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item '.NET v2.0.50727' -State 'Enabled' -RegistryDetail 'SystemDefaultTlsVersions=1'
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Name SchUseStrongCrypto -Value 1 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item '.NET v2.0.50727' -State 'Enabled' -RegistryDetail 'SchUseStrongCrypto=1'
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item '.NET v4.0.30319' -State 'Enabled' -RegistryDetail 'SystemDefaultTlsVersions=1'
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' -Name SchUseStrongCrypto -Value 1 -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item '.NET v4.0.30319' -State 'Enabled' -RegistryDetail 'SchUseStrongCrypto=1'
if (Test-Path 'HKLM:\SOFTWARE\Wow6432Node') {
    New-Item 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727' -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
    Write-RemediateLog -Item '.NET Wow6432Node v2.0.50727' -State 'Enabled' -RegistryDetail 'SystemDefaultTlsVersions=1'
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v2.0.50727' -Name SchUseStrongCrypto -Value 1 -PropertyType DWord -Force | Out-Null
    Write-RemediateLog -Item '.NET Wow6432Node v2.0.50727' -State 'Enabled' -RegistryDetail 'SchUseStrongCrypto=1'
    New-Item 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' -Force | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' -Name SystemDefaultTlsVersions -Value 1 -PropertyType DWord -Force | Out-Null
    Write-RemediateLog -Item '.NET Wow6432Node v4.0.30319' -State 'Enabled' -RegistryDetail 'SystemDefaultTlsVersions=1'
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' -Name SchUseStrongCrypto -Value 1 -PropertyType DWord -Force | Out-Null
    Write-RemediateLog -Item '.NET Wow6432Node v4.0.30319' -State 'Enabled' -RegistryDetail 'SchUseStrongCrypto=1'
}

# https://support.microsoft.com/en-us/help/3140245/update-to-enable-tls-1-1-and-tls-1-2-as-a-default-secure-protocols-in
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' -Name DefaultSecureProtocols -Value $defaultSecureProtocolsSum -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item 'WinHTTP' -State 'Enabled' -RegistryDetail "DefaultSecureProtocols=$defaultSecureProtocolsSum"
if (Test-Path 'HKLM:\SOFTWARE\Wow6432Node') {
    # WinHttp key may be missing on some machines — create it if absent.
    New-Item 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' -Name DefaultSecureProtocols -Value $defaultSecureProtocolsSum -PropertyType DWord -Force | Out-Null
    Write-RemediateLog -Item 'WinHTTP Wow6432Node' -State 'Enabled' -RegistryDetail "DefaultSecureProtocols=$defaultSecureProtocolsSum"
}

# Machine-wide default only — per-user SecureProtocols is handled separately below.
New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings' -Name SecureProtocols -Value $defaultSecureProtocolsSum -PropertyType DWord -Force | Out-Null
Write-RemediateLog -Item 'Internet Settings (machine-wide)' -State 'Enabled' -RegistryDetail "SecureProtocols=$defaultSecureProtocolsSum"

# --- Per-user SecureProtocols (online + offline hives) ---

Write-Host '--------------------------------------------------------------------------------'
Write-Host 'Applying per-user SecureProtocols (online and offline profiles)...'
Write-Host '--------------------------------------------------------------------------------'

# Applies SecureProtocols to every real user hive — both online (HKEY_USERS) and offline (NTUSER.DAT).

function Set-UserTls13 {
    param (
        [Parameter(Mandatory = $true)][string]$HiveRoot,
        [Parameter(Mandatory = $true)][string]$UserLabel,
        [Parameter(Mandatory = $true)][int]$SecureProtocolsValue
    )

    $userPath = "$HiveRoot\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    try {
        if (-not (Test-Path $userPath)) {
            New-Item -Path $userPath -Force | Out-Null
        }
        New-ItemProperty -Path $userPath -Name SecureProtocols -Value $SecureProtocolsValue -PropertyType DWord -Force | Out-Null
        return "Enabled (SecureProtocols=$SecureProtocolsValue): $UserLabel"
    } catch {
        return "FAILED: $UserLabel SecureProtocols not set ($($_.Exception.Message))"
    }
}

$userResults = @()

# Online user hives — excludes SYSTEM / LOCAL SERVICE / NETWORK SERVICE (not real users).
$excludedSIDs = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

# HKEY_USERS only contains hives for logged-on accounts; _Classes/.DEFAULT are filtered out.
$onlineUsers = Get-ChildItem 'Registry::HKEY_USERS' | Where-Object {
    $_.Name -notmatch '_Classes$' -and
    $_.PSChildName -ne '.DEFAULT' -and
    ($excludedSIDs -notcontains $_.PSChildName)
}

foreach ($user in $onlineUsers) {
    $userResults += Set-UserTls13 -HiveRoot "Registry::HKEY_USERS\$($user.PSChildName)" -UserLabel "User $($user.PSChildName)" -SecureProtocolsValue $defaultSecureProtocolsSum
}

# Offline profiles (C:\Users) — skip profiles already loaded as online hives above.
$loggedOnSIDs = $onlineUsers.PSChildName
$profileDirs = Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notin @('Default', 'Default User', 'Public', 'All Users')
}

# One-time lookup of profile path -> SID; avoids a WMI round-trip per profile inside the loop.
$profileSidLookup = @{}
try {
    Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | ForEach-Object {
        $profileSidLookup[$_.LocalPath] = $_.SID
    }
} catch {
    Write-Host "WARN: Could not query Win32_UserProfile ($($_.Exception.Message)) - offline profile matching will be skipped."
}

foreach ($profile in $profileDirs) {
    $ntUserPath = Join-Path $profile.FullName 'NTUSER.DAT'
    if (Test-Path $ntUserPath) {
        $sid = $profileSidLookup[$profile.FullName]

        if ($sid -and ($loggedOnSIDs -contains $sid)) {
            $userResults += "SKIPPED: $($profile.Name) (already loaded as SID $sid)"
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
                $userResults += Set-UserTls13 -HiveRoot "Registry::$tempHive" -UserLabel "Offline User $($profile.Name)" -SecureProtocolsValue $defaultSecureProtocolsSum
            } else {
                $userResults += "FAILED: Could not load hive for $($profile.Name) (reg load exit code $LASTEXITCODE)"
            }
        } catch {
            $userResults += "FAILED: Could not load hive for $($profile.Name) ($($_.Exception.Message))"
        } finally {
            if ($hiveLoaded) {
                # Force GC first — a lingering .NET registry handle can keep the hive locked on unload.
                [gc]::Collect()
                [gc]::WaitForPendingFinalizers()
                reg unload $tempHive 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    $userResults += "WARN: hive for $($profile.Name) may not have unloaded cleanly (exit code $LASTEXITCODE)"
                }
            }
        }
    }
}

foreach ($r in $userResults) {
    Write-Host $r
}

Stop-Transcript | Out-Null
exit 0
