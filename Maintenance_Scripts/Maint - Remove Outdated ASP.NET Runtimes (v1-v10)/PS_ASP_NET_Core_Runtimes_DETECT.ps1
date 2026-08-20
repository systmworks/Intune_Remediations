<########################################################
    Name:       PS_ASP.NET_Core_Runtimes_DETECT.ps1
    Purpose:    Detect EOL or outdated ASP.NET Core Runtimes (v1-v10)
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Registry-based detection (HKLM Uninstall keys) plus orphan folder scan
                for on-disk runtimes with no registry entry. Issue tags include arch
                suffix (x64/x86) when present in DisplayName.

    CHANGELOG:  (dd/mm/yyyy)
        31/07/2026 - v1.0 - New Script developed (folder-scan based)
        31/07/2026 - v1.1 - Switched to registry-based detection for scanner/ARP parity
        31/07/2026 - v1.2 - aspnetcore-runtime.version API; orphan folder scan; OK/Found output prefix
        05/08/2026 - v1.3 - Arch suffix in issue tags (EOL-x64 etc.)
########################################################>

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_ASP_NET_Core_Runtimes_DETECT.log"
Start-Transcript -Path $logPath -Force

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Static fallback versions for supported majors (update periodically) ---
$staticMinimums = @{
    8  = [Version]"8.0.29"
    9  = [Version]"9.0.18"
    10 = [Version]"10.0.10"
}

$eolMajors       = 1..7
$supportedMajors = @(8, 9, 10)
$runtimePath     = "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App"

$uninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

function Get-LatestVersions {
    $minimums = @{}
    foreach ($major in $supportedMajors) {
        try {
            $url           = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/$major.0/releases.json"
            $json          = Invoke-RestMethod -Uri $url -TimeoutSec 10
            $latestRelease = $json.'latest-release'
            $release       = $json.releases | Where-Object { $_.'release-version' -eq $latestRelease } | Select-Object -First 1
            $minimums[$major] = [Version]$release.'aspnetcore-runtime'.version
        } catch {
            $minimums[$major] = $staticMinimums[$major]
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

$minimumVersions = Get-LatestVersions
$issues          = @()

$installedEntries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '^Microsoft ASP\.NET Core (\d+\.\d+\.\d+) Shared Framework' }

foreach ($entry in $installedEntries) {
    $match = [regex]::Match($entry.DisplayName, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) { continue }

    try {
        $v        = [Version]$match.Groups[1].Value
        $major    = $v.Major
        $archTag  = Get-ArchTagSuffix $entry.DisplayName

        if ($major -in $eolMajors) {
            $issues += "$v(EOL$archTag)"
        } elseif ($major -in $supportedMajors) {
            if ($v -lt $minimumVersions[$major]) {
                $issues += "$v(outdated-min:$($minimumVersions[$major])$archTag)"
            }
        }
    } catch {}
}

$registeredVersions = @($installedEntries | ForEach-Object {
    $m = [regex]::Match($_.DisplayName, '(\d+\.\d+\.\d+)')
    if ($m.Success) { $m.Groups[1].Value }
})

if (Test-Path $runtimePath) {
    Get-ChildItem -Path $runtimePath -Directory | ForEach-Object {
        if ($_.Name -in $registeredVersions) { return }

        try {
            $v     = [Version]$_.Name
            $major = $v.Major

            if ($major -in $eolMajors) {
                $issues += "$($_.Name)(orphan-EOL)"
            } elseif ($major -in $supportedMajors -and $v -lt $minimumVersions[$major]) {
                $issues += "$($_.Name)(orphan-outdated-min:$($minimumVersions[$major]))"
            }
        } catch {}
    }
}

if ($issues.Count -gt 0) {
    Write-Output "Found: $($issues -join ' | ')"
    Stop-Transcript | Out-Null
    exit 1
} else {
    Write-Output "OK: No EOL or outdated ASP.NET Core Runtimes found"
    Stop-Transcript | Out-Null
    exit 0
}
