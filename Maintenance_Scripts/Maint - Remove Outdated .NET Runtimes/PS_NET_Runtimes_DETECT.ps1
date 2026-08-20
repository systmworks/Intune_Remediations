<########################################################
    Name:       PS_NET_Runtimes_DETECT.ps1
    Purpose:    Detect EOL or outdated .NET Runtime and Windows Desktop Runtime
                (combined pair - removal order enforced in REMEDIATE script).
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Registry-based detection (HKLM Uninstall keys) plus orphan folder scan
                for on-disk runtimes with no registry entry. Also scans Host FX Resolver
                and .NET Host companions (guarded - highest version never flagged).
                SDK gate: when dotnet SDK present, only EOL majors (1-7) are flagged;
                outdated v8/v9/v10 are exempt (matches REMEDIATE eol-only-sdk policy).
                Majors 8 and 9 reach EOL on 10/11/2026 - update $eolMajors then.

    CHANGELOG:  (dd/mm/yyyy)
        31/07/2026 - v1.0 - New script; combined Runtime + Desktop Runtime detection
        05/08/2026 - v1.1 - Arch-aware orphan registration (x64 vs x86); Found (N): count prefix
                             in output (pilot-tested)
########################################################>

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_NET_Runtimes_DETECT.log"
Start-Transcript -Path $logPath -Force

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

# HostFxr before Host - version digit follows separator so Host cannot match Host FX Resolver
$componentPatterns = [ordered]@{
    Desktop = '^Microsoft Windows Desktop Runtime[\s-]+(\d+\.\d+\.\d+)'
    Runtime = '^Microsoft \.NET (?:Core )?Runtime[\s-]+(\d+\.\d+\.\d+)'
    HostFxr = '^Microsoft \.NET (?:Core )?Host FX Resolver[\s-]+(\d+\.\d+\.\d+)'
    Host    = '^Microsoft \.NET (?:Core )?Host[\s-]+(\d+\.\d+\.\d+)'
}

$orphanScanPaths = @(
    @{ Component = 'Desktop'; ArchKey = 'x64'; Path = 'C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App' }
    @{ Component = 'Runtime'; ArchKey = 'x64'; Path = 'C:\Program Files\dotnet\shared\Microsoft.NETCore.App' }
    @{ Component = 'Desktop'; ArchKey = 'x86'; Path = 'C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App' }
    @{ Component = 'Runtime'; ArchKey = 'x86'; Path = 'C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App' }
    @{ Component = 'HostFxr'; ArchKey = 'x64'; Path = 'C:\Program Files\dotnet\host\fxr' }
)

$sdkPresent = @(Get-ChildItem 'C:\Program Files\dotnet\sdk' -Directory -ErrorAction SilentlyContinue).Count -gt 0

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

function Test-HigherComponentVersionPresent {
    param(
        [string]$Component,
        [Version]$Version,
        [string[]]$RegisteredByComponent,
        [string[]]$DiskByComponent
    )

    foreach ($vs in $RegisteredByComponent) {
        try {
            $candidate = [Version]$vs
            if ($candidate -gt $Version) { return $true }
        } catch {}
    }

    foreach ($vs in $DiskByComponent) {
        try {
            $candidate = [Version]$vs
            if ($candidate -gt $Version) { return $true }
        } catch {}
    }

    return $false
}

function Test-MinimumPresentForMajor {
    param(
        [string]$Component,
        [int]$Major,
        [Version]$MinVersion,
        [hashtable]$RegisteredVersionsByComponent,
        [hashtable]$DiskVersionsByComponent
    )

    $registered = @($RegisteredVersionsByComponent[$Component])
    $disk       = @($DiskVersionsByComponent[$Component])

    foreach ($vs in $registered) {
        try {
            if ([Version]$vs -ge $MinVersion -and ([Version]$vs).Major -eq $Major) { return $true }
        } catch {}
    }

    foreach ($vs in $disk) {
        try {
            if ([Version]$vs -ge $MinVersion -and ([Version]$vs).Major -eq $Major) { return $true }
        } catch {}
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

function Add-Issue {
    param(
        [ref]$Issues,
        [ref]$SeenKeys,
        [string]$Component,
        [string]$VersionString,
        [string]$ReasonTag
    )

    $key = "$Component|$VersionString|$ReasonTag"
    if ($SeenKeys.Value -contains $key) { return }
    $SeenKeys.Value += $key
    $Issues.Value += "${Component}:${VersionString}($ReasonTag)"
}

$minimumVersions = Get-LatestVersions
$issues          = @()
$seenKeys        = @()

$allEntries = @(Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue)

$registeredMaps          = Get-RegisteredVersionMaps
$registeredByComponent   = $registeredMaps.ByComponent
$registeredByComponentArch = $registeredMaps.ByComponentArch

$diskVersionsByComponent = @{
    Desktop = @()
    Runtime = @()
    HostFxr = @()
    Host    = @()
}

foreach ($scan in $orphanScanPaths) {
    if (-not (Test-Path $scan.Path)) { continue }
    $names = @(Get-ChildItem -Path $scan.Path -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    foreach ($n in $names) {
        if ($n -notin $diskVersionsByComponent[$scan.Component]) {
            $diskVersionsByComponent[$scan.Component] += $n
        }
    }
}

foreach ($entry in $allEntries) {
    $parsed = Get-ComponentFromDisplayName -DisplayName $entry.DisplayName
    if (-not $parsed) { continue }

    $versionString = $parsed.Version
    $component     = $parsed.Component
    $archTag       = Get-ArchTagSuffix $entry.DisplayName

    try {
        $v     = [Version]$versionString
        $major = $v.Major

        if ($component -in @('HostFxr', 'Host')) {
            $higherPresent = Test-HigherComponentVersionPresent `
                -Component $component `
                -Version $v `
                -RegisteredByComponent $registeredByComponent[$component] `
                -DiskByComponent $diskVersionsByComponent[$component]
            if (-not $higherPresent) { continue }
        }

        if ($major -in $eolMajors) {
            Add-Issue -Issues ([ref]$issues) -SeenKeys ([ref]$seenKeys) `
                -Component $component -VersionString $versionString -ReasonTag "EOL$archTag"
        } elseif ($major -in $supportedMajors) {
            if ($sdkPresent) { continue }

            $minVersion = Get-MinimumForComponent -Component $component -Major $major -MinimumVersions $minimumVersions
            if ($v -lt $minVersion) {
                Add-Issue -Issues ([ref]$issues) -SeenKeys ([ref]$seenKeys) `
                    -Component $component -VersionString $versionString `
                    -ReasonTag "outdated-min:$minVersion$archTag"
            }
        }
    } catch {}
}

foreach ($scan in $orphanScanPaths) {
    $component = $scan.Component
    $basePath  = $scan.Path
    $archKey   = $scan.ArchKey
    if (-not (Test-Path $basePath)) { continue }

    $caKey = Get-ComponentArchKey -Component $component -ArchKey $archKey
    $registeredForComponentArch = @()
    if ($registeredByComponentArch.ContainsKey($caKey)) {
        $registeredForComponentArch = @($registeredByComponentArch[$caKey])
    }

    Get-ChildItem -Path $basePath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $folderVersion = $_.Name
        if ($folderVersion -in $registeredForComponentArch) { return }

        try {
            $v     = [Version]$folderVersion
            $major = $v.Major

            if ($component -in @('HostFxr', 'Host')) {
                $higherPresent = Test-HigherComponentVersionPresent `
                    -Component $component `
                    -Version $v `
                    -RegisteredByComponent $registeredByComponent[$component] `
                    -DiskByComponent $diskVersionsByComponent[$component]
                if (-not $higherPresent) { return }
            }

            $isLocked = Test-FolderLocked -Path $_.FullName
            if ($isLocked) {
                Add-Issue -Issues ([ref]$issues) -SeenKeys ([ref]$seenKeys) `
                    -Component $component -VersionString $folderVersion -ReasonTag 'orphan-locked'
                return
            }

            if ($major -in $eolMajors) {
                Add-Issue -Issues ([ref]$issues) -SeenKeys ([ref]$seenKeys) `
                    -Component $component -VersionString $folderVersion -ReasonTag 'orphan-EOL'
            } elseif ($major -in $supportedMajors) {
                if ($sdkPresent) { return }

                $minVersion = Get-MinimumForComponent -Component $component -Major $major -MinimumVersions $minimumVersions
                if ($v -lt $minVersion) {
                    if (Test-MinimumPresentForMajor -Component $component -Major $major -MinVersion $minVersion `
                        -RegisteredVersionsByComponent $registeredByComponent -DiskVersionsByComponent $diskVersionsByComponent) {
                        Add-Issue -Issues ([ref]$issues) -SeenKeys ([ref]$seenKeys) `
                            -Component $component -VersionString $folderVersion `
                            -ReasonTag "orphan-outdated-min:$minVersion"
                    }
                }
            }
        } catch {}
    }
}

if ($issues.Count -gt 0) {
    Write-Output "Found ($($issues.Count)): $($issues -join ' | ')"
    Stop-Transcript | Out-Null
    exit 1
} else {
    Write-Output "OK: No EOL or outdated .NET Runtime / Desktop Runtime found"
    Stop-Transcript | Out-Null
    exit 0
}
