<########################################################
    Name:       PS_NET_Runtimes_REMEDIATE.ps1
    Purpose:    Remove EOL or outdated .NET Runtime and Windows Desktop Runtime in a
                single coordinated pass. Desktop Runtime is removed before .NET Runtime
                (dependency order). Host FX Resolver and .NET Host companions are removed
                only when a strictly higher version of that component remains.
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Uninstalls via Burn bundle (preferred) or msiexec against registered MSI
                product codes. Orphan folder force-delete only when no registry entry;
                locked folders skipped via pre-flight Test-FolderLocked (never partial
                delete). SDK gate: when dotnet SDK present, only EOL majors (1-7) removed;
                outdated v8/v9/v10 skipped without setting remediationFailed.
                Parity guard: .NET Runtime not removed while matching Desktop or ASP.NET
                Core shared framework remains at same version.
                Majors 8 and 9 reach EOL on 10/11/2026 - update $eolMajors then.

    CHANGELOG:  (dd/mm/yyyy)
        31/07/2026 - v1.0 - New script; combined Runtime + Desktop Runtime remediation
        05/08/2026 - v1.1 - Process all registry entries per version/arch (fixes duplicate MSI
                             left behind); fix bundle vs MsiExec detection; arch-aware removal
                             and orphan tracking for mixed x86/x64 fleets; fix false FAILED on
                             exe/bundle uninstall (pipeline exit-code pollution); parity guard
                             uses Desktop registry only, not lingering disk folders (pilot-tested)
########################################################>

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_NET_Runtimes_REMEDIATE.log"
Start-Transcript -Path $logPath -Append -Force

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Static fallback versions for supported majors (update periodically) ---
$staticMinimums = @{
    Runtime = @{ 8 = [Version]"8.0.29"; 9 = [Version]"9.0.18"; 10 = [Version]"10.0.10" }
    Desktop = @{ 8 = [Version]"8.0.29"; 9 = [Version]"9.0.18"; 10 = [Version]"10.0.10" }
}

$eolMajors       = 1..7
$supportedMajors = @(8, 9, 10)

$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$componentPatterns = [ordered]@{
    Desktop = '^Microsoft Windows Desktop Runtime[\s-]+(\d+\.\d+\.\d+)'
    Runtime = '^Microsoft \.NET (?:Core )?Runtime[\s-]+(\d+\.\d+\.\d+)'
    HostFxr = '^Microsoft \.NET (?:Core )?Host FX Resolver[\s-]+(\d+\.\d+\.\d+)'
    Host    = '^Microsoft \.NET (?:Core )?Host[\s-]+(\d+\.\d+\.\d+)'
}

$componentOrder = @('Desktop', 'Runtime', 'HostFxr', 'Host')

$orphanScanPaths = @(
    @{ Component = 'Desktop'; ArchKey = 'x64'; Path = 'C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App' }
    @{ Component = 'Runtime'; ArchKey = 'x64'; Path = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App' }
    @{ Component = 'Desktop'; ArchKey = 'x86'; Path = 'C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App' }
    @{ Component = 'Runtime'; ArchKey = 'x86'; Path = 'C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App' }
    @{ Component = 'HostFxr'; ArchKey = 'x64'; Path = 'C:\Program Files\dotnet\host\fxr' }
)

$aspNetCorePattern = '^Microsoft ASP\.NET Core (\d+\.\d+\.\d+) (?:Shared Framework|Runtime)'

$sdkPresent = @(Get-ChildItem 'C:\Program Files\dotnet\sdk' -Directory -ErrorAction SilentlyContinue).Count -gt 0
if ($sdkPresent) {
    Write-Output "SDK present - eol-only-sdk policy active (majors 1-7 only for supported-channel outdated)"
}

function Get-LatestVersions {
    $minimums = @{ Runtime = @{}; Desktop = @{} }
    foreach ($major in $supportedMajors) {
        try {
            $url           = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$major.0/releases.json"
            $json          = Invoke-RestMethod -Uri $url -TimeoutSec 10
            $latestRelease = $json.'latest-release'
            $release       = $json.releases | Where-Object { $_.'release-version' -eq $latestRelease } | Select-Object -First 1
            $minimums.Runtime[$major] = [Version]$release.runtime.version
            $minimums.Desktop[$major] = [Version]$release.windowsdesktop.version
        } catch {
            $minimums.Runtime[$major] = $staticMinimums.Runtime[$major]
            $minimums.Desktop[$major] = $staticMinimums.Desktop[$major]
        }
    }
    return $minimums
}

function Get-ArchTagSuffix {
    param([string]$DisplayName)

    if ($DisplayName -match '\(x64\)')   { return '-x64' }
    if ($DisplayName -match '\(x86\)')   { return '-x86' }
    if ($DisplayName -match '\(arm64\)') { return '-arm64' }
    return ''
}

function Get-ComponentFromDisplayName {
    param([string]$DisplayName)

    foreach ($kv in $componentPatterns.GetEnumerator()) {
        $m = [regex]::Match($DisplayName, $kv.Value)
        if ($m.Success) {
            return @{ Component = $kv.Key; Version = $m.Groups[1].Value }
        }
    }
    return $null
}

function Get-MinimumForComponent {
    param(
        [string]$Component,
        [int]$Major,
        [hashtable]$MinimumVersions
    )

    switch ($Component) {
        'Desktop' { return $MinimumVersions.Desktop[$Major] }
        'Runtime' { return $MinimumVersions.Runtime[$Major] }
        default   { return $MinimumVersions.Runtime[$Major] }
    }
}

function Get-ArchKeyFromDisplayName {
    param([string]$DisplayName)

    $tag = Get-ArchTagSuffix $DisplayName
    switch ($tag) {
        '-x86'   { return 'x86' }
        '-arm64' { return 'arm64' }
        '-x64'   { return 'x64' }
        default  { return 'x64' }
    }
}

function Get-ComponentArchKey {
    param(
        [string]$Component,
        [string]$ArchKey
    )

    return "$Component|$ArchKey"
}

function Test-IsBundleEntry {
    param($RegistryEntry)

    if ($RegistryEntry.BundleProviderKey) { return $true }

    $uninstall = $RegistryEntry.QuietUninstallString
    if ([string]::IsNullOrWhiteSpace($uninstall)) {
        $uninstall = $RegistryEntry.UninstallString
    }
    if ([string]::IsNullOrWhiteSpace($uninstall)) { return $false }
    if ($uninstall -match '(?i)MsiExec') { return $false }

    return ($uninstall -match 'Package Cache')
}

function Get-RegisteredVersionMaps {
    $byComponent = @{
        Desktop = @()
        Runtime = @()
        HostFxr = @()
        Host    = @()
    }
    $byComponentArch = @{}

    $entries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue
    foreach ($entry in $entries) {
        $parsed = Get-ComponentFromDisplayName -DisplayName $entry.DisplayName
        if (-not $parsed) { continue }

        $archKey = Get-ArchKeyFromDisplayName $entry.DisplayName
        $caKey   = Get-ComponentArchKey -Component $parsed.Component -ArchKey $archKey

        if (-not $byComponentArch.ContainsKey($caKey)) {
            $byComponentArch[$caKey] = @()
        }
        if ($parsed.Version -notin $byComponentArch[$caKey]) {
            $byComponentArch[$caKey] += $parsed.Version
        }
        if ($parsed.Version -notin $byComponent[$parsed.Component]) {
            $byComponent[$parsed.Component] += $parsed.Version
        }
    }

    return @{ ByComponent = $byComponent; ByComponentArch = $byComponentArch }
}

function Get-RegisteredVersionsByComponent {
    return (Get-RegisteredVersionMaps).ByComponent
}

function Get-DiskVersionsByComponent {
    $byComponent = @{
        Desktop = @()
        Runtime = @()
        HostFxr = @()
        Host    = @()
    }

    foreach ($scan in $orphanScanPaths) {
        if (-not (Test-Path $scan.Path)) { continue }
        Get-ChildItem -Path $scan.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -notin $byComponent[$scan.Component]) {
                $byComponent[$scan.Component] += $_.Name
            }
        }
    }

    return $byComponent
}

function Test-MinimumPresentForMajor {
    param(
        [string]$Component,
        [int]$Major,
        [Version]$MinVersion,
        [hashtable]$RegisteredByComponent,
        [hashtable]$DiskByComponent
    )

    foreach ($vs in @($RegisteredByComponent[$Component])) {
        try {
            if ([Version]$vs -ge $MinVersion -and ([Version]$vs).Major -eq $Major) { return $true }
        } catch {}
    }

    foreach ($vs in @($DiskByComponent[$Component])) {
        try {
            if ([Version]$vs -ge $MinVersion -and ([Version]$vs).Major -eq $Major) { return $true }
        } catch {}
    }

    return $false
}

function Test-HigherComponentVersionPresent {
    param(
        [string]$Component,
        [Version]$Version,
        [hashtable]$RegisteredByComponent,
        [hashtable]$DiskByComponent
    )

    foreach ($vs in @($RegisteredByComponent[$Component])) {
        try {
            if ([Version]$vs -gt $Version) { return $true }
        } catch {}
    }

    foreach ($vs in @($DiskByComponent[$Component])) {
        try {
            if ([Version]$vs -gt $Version) { return $true }
        } catch {}
    }

    return $false
}

function Test-VersionBlockedByParity {
    param(
        [string]$VersionString,
        [hashtable]$RegisteredByComponent
    )

    # Desktop: registry only — disk folders often linger after msiexec until reboot;
    # blocking Runtime on a leftover folder causes false parity-block in the same run
    # after Desktop was already uninstalled successfully.
    if ($VersionString -in @($RegisteredByComponent.Desktop)) { return $true }

    $aspNetFolder = "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\$VersionString"
    if (Test-Path $aspNetFolder) { return $true }

    $aspNetFolderX86 = "C:\Program Files (x86)\dotnet\shared\Microsoft.AspNetCore.App\$VersionString"
    if (Test-Path $aspNetFolderX86) { return $true }

    foreach ($entry in $script:AspNetRegistryEntries) {
        $m = [regex]::Match($entry.DisplayName, '(\d+\.\d+\.\d+)')
        if ($m.Success -and $m.Groups[1].Value -eq $VersionString) { return $true }
    }

    return $false
}

function Test-FolderLocked {
    param([string]$Path)

    foreach ($file in Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue) {
        try {
            $stream = [System.IO.File]::Open($file.FullName, 'Open', 'ReadWrite', 'None')
            $stream.Close()
            $stream.Dispose()
        } catch {
            return $true
        }
    }
    return $false
}

function Uninstall-DotNetComponent {
    param(
        $RegistryEntry,
        [string]$Component,
        [string]$VersionString
    )

    $uninstallString = $RegistryEntry.QuietUninstallString
    if ([string]::IsNullOrWhiteSpace($uninstallString)) {
        $uninstallString = $RegistryEntry.UninstallString
    }

    if ([string]::IsNullOrWhiteSpace($uninstallString)) {
        return 1619
    }

    $archLabel = Get-ArchTagSuffix $RegistryEntry.DisplayName
    if ($archLabel -eq '') { $archLabel = 'unknown' }
    $msiLog = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\netruntime_${Component}_${VersionString}${archLabel}.msi.log"

    $productCodeMatch = [regex]::Match($uninstallString, '\{[0-9A-Fa-f\-]{36}\}')
    if ($productCodeMatch.Success -and $uninstallString -match '(?i)MsiExec') {
        $productCode = $productCodeMatch.Value
        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/x $productCode /quiet /norestart IGNOREDEPENDENCIES=ALL /log `"$msiLog`"" `
            -Wait -PassThru -WindowStyle Hidden
        return $proc.ExitCode
    }

    if ($uninstallString -match '(?i)Package Cache.*\.exe') {
        if ($uninstallString -match '^"(?<exe>[^"]+\.exe)"\s*(?<args>.*)$') {
            $exePath = $Matches.exe
            $exeArgs = $Matches.args.Trim()
        } else {
            $parts   = $uninstallString -split '\s+', 2
            $exePath = $parts[0].Trim('"')
            $exeArgs = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        }
        if ($exeArgs -notmatch '(?i)/quiet') {
            $exeArgs = "$exeArgs /quiet /norestart".Trim()
        }
        $proc = Start-Process -FilePath $exePath -ArgumentList $exeArgs -Wait -PassThru -WindowStyle Hidden
        return $proc.ExitCode
    }

    if ($productCodeMatch.Success) {
        $productCode = $productCodeMatch.Value
        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/x $productCode /quiet /norestart IGNOREDEPENDENCIES=ALL /log `"$msiLog`"" `
            -Wait -PassThru -WindowStyle Hidden
        return $proc.ExitCode
    }

    if ($uninstallString -match '(?i)\.exe') {
        if ($uninstallString -match '^"(?<exe>[^"]+\.exe)"\s*(?<args>.*)$') {
            $exePath = $Matches.exe
            $exeArgs = $Matches.args.Trim()
        } else {
            $parts   = $uninstallString -split '\s+', 2
            $exePath = $parts[0].Trim('"')
            $exeArgs = if ($parts.Count -gt 1) { $parts[1] } else { '' }
        }
        if ($exeArgs -notmatch '(?i)/quiet') {
            $exeArgs = "$exeArgs /quiet /norestart".Trim()
        }
        $proc = Start-Process -FilePath $exePath -ArgumentList $exeArgs -Wait -PassThru -WindowStyle Hidden
        return $proc.ExitCode
    }

    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c `"$uninstallString`" /quiet /norestart" `
        -Wait -PassThru -WindowStyle Hidden
    return $proc.ExitCode
}

function Test-BundleStillRegistered {
    param(
        [string]$Component,
        [string]$VersionString,
        [string]$ArchTag
    )

    $entries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue
    foreach ($entry in $entries) {
        $parsed = Get-ComponentFromDisplayName -DisplayName $entry.DisplayName
        if (-not $parsed) { continue }
        if ($parsed.Component -ne $Component) { continue }
        if ($parsed.Version -ne $VersionString) { continue }
        if ((Get-ArchTagSuffix $entry.DisplayName) -ne $ArchTag) { continue }
        if (Test-IsBundleEntry $entry) { return $true }
    }

    return $false
}

$minimumVersions = Get-LatestVersions
foreach ($major in $supportedMajors) {
    Write-Output "Minimum Runtime v$major : $($minimumVersions.Runtime[$major])"
    Write-Output "Minimum Desktop v$major : $($minimumVersions.Desktop[$major])"
}

$remediationFailed     = $false
$removed               = @()
$removedVersionStrings = @()
$skipped               = @()
$orphaned              = @()
$processedEntryKeys    = @()

$allRawEntries = @(Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue)
$script:AspNetRegistryEntries = @($allRawEntries | Where-Object { $_.DisplayName -match $aspNetCorePattern })
$parsedEntries = @()

foreach ($entry in $allRawEntries) {
    $parsed = Get-ComponentFromDisplayName -DisplayName $entry.DisplayName
    if (-not $parsed) { continue }

    $parsedEntries += [PSCustomObject]@{
        Component = $parsed.Component
        Version   = $parsed.Version
        ArchTag   = Get-ArchTagSuffix $entry.DisplayName
        ArchKey   = Get-ArchKeyFromDisplayName $entry.DisplayName
        Entry     = $entry
        IsBundle  = Test-IsBundleEntry $entry
        EntryKey  = "$($entry.PSPath)|$($entry.PSChildName)"
    }
}

$registeredMaps            = Get-RegisteredVersionMaps
$registeredByComponent     = $registeredMaps.ByComponent
$registeredByComponentArch = $registeredMaps.ByComponentArch
$diskByComponent           = Get-DiskVersionsByComponent

foreach ($component in $componentOrder) {
    $componentEntries = @($parsedEntries | Where-Object { $_.Component -eq $component })
    $sortedEntries    = @($componentEntries | Sort-Object @{ Expression = { -not $_.IsBundle } }, Version, ArchTag, EntryKey)

    foreach ($item in $sortedEntries) {
        $entry         = $item.Entry
        $versionString = $item.Version
        $archTag       = $item.ArchTag
        $componentName = $item.Component

        if ($item.EntryKey -in $processedEntryKeys) { continue }

        if (-not $item.IsBundle) {
            if (Test-BundleStillRegistered -Component $componentName -VersionString $versionString -ArchTag $archTag) {
                Write-Output "SKIP MSI: $componentName $versionString$archTag - bundle still registered for same version/arch"
                continue
            }
        }

        try {
            $v     = [Version]$versionString
            $major = $v.Major

            if ($componentName -in @('HostFxr', 'Host')) {
                $higherPresent = Test-HigherComponentVersionPresent `
                    -Component $componentName -Version $v `
                    -RegisteredByComponent $registeredByComponent -DiskByComponent $diskByComponent
                if (-not $higherPresent) {
                    Write-Output "SKIP COMPANION: $componentName $versionString$archTag - highest remaining version"
                    $processedEntryKeys += $item.EntryKey
                    continue
                }
            }

            if ($componentName -eq 'Runtime') {
                if (Test-VersionBlockedByParity -VersionString $versionString `
                    -RegisteredByComponent $registeredByComponent) {
                    Write-Output "SKIP PARITY: Runtime $versionString$archTag - Desktop or ASP.NET Core still at this version"
                    $skipped += "Runtime:$versionString$archTag(parity-blocked)"
                    $remediationFailed = $true
                    $processedEntryKeys += $item.EntryKey
                    continue
                }
            }

            $shouldRemove = $false
            $reasonTag    = ""

            if ($major -in $eolMajors) {
                $shouldRemove = $true
                $reasonTag    = "EOL$archTag"
            } elseif ($major -in $supportedMajors) {
                $minVersion = Get-MinimumForComponent -Component $componentName -Major $major -MinimumVersions $minimumVersions

                if ($v -ge $minVersion) {
                    Write-Output "CURRENT: $componentName $versionString$archTag - no action needed"
                    $processedEntryKeys += $item.EntryKey
                    continue
                }

                if ($sdkPresent) {
                    Write-Output "SKIPPING: $componentName $versionString$archTag - SDK present (EOL-only policy)"
                    $skipped += "$componentName`:$versionString$archTag(SDK present)"
                    $processedEntryKeys += $item.EntryKey
                    continue
                }

                if (Test-MinimumPresentForMajor -Component $componentName -Major $major -MinVersion $minVersion `
                    -RegisteredByComponent $registeredByComponent -DiskByComponent $diskByComponent) {
                    $shouldRemove = $true
                    $reasonTag    = "outdated$archTag"
                } else {
                    Write-Output "SKIPPING: $componentName $versionString$archTag - minimum $minVersion not yet deployed"
                    $skipped += "$componentName`:$versionString$archTag(min:$minVersion not yet deployed)"
                    $remediationFailed = $true
                    $processedEntryKeys += $item.EntryKey
                    continue
                }
            } else {
                $processedEntryKeys += $item.EntryKey
                continue
            }

            if ($shouldRemove) {
                $uninstallLabel = if ($item.IsBundle) { 'bundle' } else { 'msi' }
                Write-Output "Uninstalling ($reasonTag): $componentName $versionString$archTag via $uninstallLabel $($entry.PSChildName)"
                $exitCode = Uninstall-DotNetComponent -RegistryEntry $entry -Component $componentName -VersionString $versionString

                if ($exitCode -eq 1619) {
                    Write-Output "FAILED: No UninstallString for $componentName $versionString$archTag ($($entry.PSChildName))"
                }

                if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                    Write-Output "SUCCESS (exit $exitCode): $componentName $versionString$archTag"
                    $removed += "$componentName`:$versionString($reasonTag)"
                    $trackKey = Get-ComponentArchKey -Component $componentName -ArchKey $item.ArchKey
                    $trackKey = "$trackKey|$versionString"
                    if ($removedVersionStrings -notcontains $trackKey) {
                        $removedVersionStrings += $trackKey
                    }
                } else {
                    Write-Output "FAILED (exit $exitCode): $componentName $versionString$archTag"
                    $skipped += "$componentName`:$versionString$archTag(msiexec exit $exitCode)"
                    $remediationFailed = $true
                }
            }

            $processedEntryKeys += $item.EntryKey
        } catch {
            Write-Output "ERROR processing $componentName $versionString$archTag`: $_"
            $remediationFailed = $true
            $processedEntryKeys += $item.EntryKey
        }
    }

    $registeredMaps            = Get-RegisteredVersionMaps
    $registeredByComponent     = $registeredMaps.ByComponent
    $registeredByComponentArch = $registeredMaps.ByComponentArch
    $diskByComponent           = Get-DiskVersionsByComponent
}

# --- Orphan check: folders on disk with no matching registry entry ---
$registeredMapsFresh            = Get-RegisteredVersionMaps
$registeredByComponentFresh     = $registeredMapsFresh.ByComponent
$registeredByComponentArchFresh = $registeredMapsFresh.ByComponentArch
$diskByComponentFresh           = Get-DiskVersionsByComponent

foreach ($scan in $orphanScanPaths) {
    $component = $scan.Component
    $basePath  = $scan.Path
    $archKey   = $scan.ArchKey
    if (-not (Test-Path $basePath)) { continue }

    $caKey = Get-ComponentArchKey -Component $component -ArchKey $archKey
    $registeredForComponentArch = @()
    if ($registeredByComponentArchFresh.ContainsKey($caKey)) {
        $registeredForComponentArch = @($registeredByComponentArchFresh[$caKey])
    }

    Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $folderVersion = $_.Name
        $folderPath    = $_.FullName
        $trackKey      = "$caKey|$folderVersion"

        if ($folderVersion -in $registeredForComponentArch) { return }
        if ($trackKey -in $removedVersionStrings) {
            Write-Output "PENDING: $component $folderVersion ($archKey) - uninstalled via msiexec/bundle this run; folder cleanup deferred"
            return
        }

        try {
            $v     = [Version]$folderVersion
            $major = $v.Major

            if ($component -in @('HostFxr', 'Host')) {
                $higherPresent = Test-HigherComponentVersionPresent `
                    -Component $component -Version $v `
                    -RegisteredByComponent $registeredByComponentFresh -DiskByComponent $diskByComponentFresh
                if (-not $higherPresent) {
                    Write-Output "SKIP ORPHAN COMPANION: $component $folderVersion - highest remaining version"
                    return
                }
            }

            if ($component -eq 'Runtime') {
                if (Test-VersionBlockedByParity -VersionString $folderVersion `
                    -RegisteredByComponent $registeredByComponentFresh) {
                    Write-Output "SKIP ORPHAN PARITY: Runtime $folderVersion - Desktop or ASP.NET Core still at this version"
                    $skipped += "Runtime:$folderVersion(orphan-parity-blocked)"
                    $remediationFailed = $true
                    return
                }
            }

            $shouldRemoveOrphan = $false
            $orphanReason       = ""

            if ($major -in $eolMajors) {
                $shouldRemoveOrphan = $true
                $orphanReason       = "orphan-removed"
            } elseif ($major -in $supportedMajors) {
                if ($sdkPresent) {
                    Write-Output "SKIPPING orphan: $component $folderVersion - SDK present (EOL-only policy)"
                    return
                }

                $minVersion = Get-MinimumForComponent -Component $component -Major $major -MinimumVersions $minimumVersions
                if ($v -lt $minVersion) {
                    if (Test-MinimumPresentForMajor -Component $component -Major $major -MinVersion $minVersion `
                        -RegisteredByComponent $registeredByComponentFresh -DiskByComponent $diskByComponentFresh) {
                        $shouldRemoveOrphan = $true
                        $orphanReason       = "orphan-removed"
                    } else {
                        Write-Output "SKIPPING orphan: $component $folderVersion - minimum $minVersion not yet deployed"
                        $skipped += "$component`:$folderVersion(orphan-min:$minVersion not yet deployed)"
                        $remediationFailed = $true
                        return
                    }
                } else {
                    return
                }
            } else {
                return
            }

            if ($shouldRemoveOrphan) {
                if (Test-FolderLocked -Path $folderPath) {
                    Write-Output "LOCKED: $component $folderVersion - orphan folder in use; skipping force-delete"
                    $skipped += "$component`:$folderVersion(orphan-locked)"
                    $remediationFailed = $true
                    return
                }

                Write-Output "ORPHAN (no registry entry) removing folder: $folderPath"
                Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop
                $orphaned += "$component`:$folderVersion($orphanReason)"
            }
        } catch {
            Write-Output "ERROR removing orphan folder $component $folderVersion`: $_"
            $remediationFailed = $true
        }
    }
}

# --- Build single line output for Intune ---
$parts = @()
if ($removed.Count -gt 0)  { $parts += "Removed: $($removed -join ' | ')" }
if ($orphaned.Count -gt 0) { $parts += "Orphaned: $($orphaned -join ' | ')" }
if ($skipped.Count -gt 0)  { $parts += "Skipped: $($skipped -join ' | ')" }
if ($parts.Count -eq 0)    { $parts += "Nothing to remediate" }

$outputLine = if ($remediationFailed) {
    "INCOMPLETE: $($parts -join ' -- ')"
} else {
    "SUCCESS: $($parts -join ' -- ')"
}

Write-Output $outputLine
Stop-Transcript | Out-Null

if ($remediationFailed) { exit 1 } else { exit 0 }
