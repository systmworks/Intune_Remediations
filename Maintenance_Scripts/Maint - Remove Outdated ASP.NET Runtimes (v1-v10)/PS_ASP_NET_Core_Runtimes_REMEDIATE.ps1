<########################################################
    Name:       PS_ASP.NET_Core_Runtimes_REMEDIATE.ps1
    Purpose:    Remove EOL ASP.NET Core Runtimes; remove outdated v8/v9/v10 only when a
                supported minimum is already present on the same machine.
                Uninstalls via msiexec against the registered MSI product code instead of
                deleting the shared-framework folder directly - this clears the
                Programs & Features / Uninstall registry entry (what vuln scanners read)
                and lets the installer handle any in-use files (pending-reboot rename)
                instead of a raw delete corrupting a running app mid-file.
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Falls back to a forced folder delete ONLY when a shared-framework folder
                exists on disk with no matching registry/MSI entry (orphaned install) -
                logged separately as ORPHAN so it stays auditable rather than silent.
                Folders left on disk after a successful msiexec uninstall in the same run
                are not force-deleted; msiexec owns pending-reboot cleanup.
                Processes every registry entry (x64 and x86) in a single run.

    CHANGELOG:  (dd/mm/yyyy)
        31/07/2026 - v1.0 - New Script developed (force-delete based)
        31/07/2026 - v1.1 - Switched to registry/msiexec-based uninstall; orphan-folder
                             fallback; matches DETECT v1.1 source of truth
        31/07/2026 - v1.2 - Fix Get-LatestVersions return; aspnetcore-runtime.version API;
                             orphan PMPC gate; fresh registry before orphan pass
        05/08/2026 - v1.3 - Uninstall all x64/x86 registry entries per run;
                             IGNOREDEPENDENCIES=ALL; skip orphan pass for same-run msiexec uninstalls
########################################################>

$logPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_ASP_NET_Core_Runtimes_REMEDIATE.log"
Start-Transcript -Path $logPath -Append -Force

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

function Get-RegisteredVersionStrings {
    $entries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match '^Microsoft ASP\.NET Core (\d+\.\d+\.\d+) Shared Framework' }
    @($entries | ForEach-Object {
        $m = [regex]::Match($_.DisplayName, '(\d+\.\d+\.\d+)')
        if ($m.Success) { $m.Groups[1].Value }
    })
}

function Get-ArchTagSuffix {
    param([string]$DisplayName)

    if ($DisplayName -match '\(x64\)')   { return '-x64' }
    if ($DisplayName -match '\(x86\)')   { return '-x86' }
    if ($DisplayName -match '\(arm64\)') { return '-arm64' }
    return ''
}

function Test-MinimumPresentForMajor {
    param(
        [int]$Major,
        [Version]$MinVersion,
        [string[]]$RegisteredVersions,
        [string[]]$DiskVersions
    )

    foreach ($vs in $RegisteredVersions) {
        try {
            if ([Version]$vs -ge $MinVersion -and ([Version]$vs).Major -eq $Major) { return $true }
        } catch {}
    }

    foreach ($vs in $DiskVersions) {
        try {
            if ([Version]$vs -ge $MinVersion -and ([Version]$vs).Major -eq $Major) { return $true }
        } catch {}
    }

    return $false
}

function Uninstall-AspNetCoreRuntime {
    param($RegistryEntry, $VersionString)

    $uninstallString = $RegistryEntry.UninstallString
    if ([string]::IsNullOrWhiteSpace($uninstallString) -and $RegistryEntry.QuietUninstallString) {
        $uninstallString = $RegistryEntry.QuietUninstallString
    }

    if ([string]::IsNullOrWhiteSpace($uninstallString)) {
        Write-Output "FAILED: No UninstallString for $VersionString ($($RegistryEntry.PSChildName))"
        return 1619
    }

    $archLabel = Get-ArchTagSuffix $RegistryEntry.DisplayName
    if ($archLabel -eq '') { $archLabel = 'unknown' }
    $msiLog = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\aspnetcore_${VersionString}${archLabel}.msi.log"

    $productCodeMatch = [regex]::Match($uninstallString, '\{[0-9A-Fa-f\-]{36}\}')
    if ($productCodeMatch.Success) {
        $productCode = $productCodeMatch.Value
        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/x $productCode /quiet /norestart IGNOREDEPENDENCIES=ALL /log `"$msiLog`"" `
            -Wait -PassThru -WindowStyle Hidden
        return $proc.ExitCode
    }

    if ($uninstallString -match '(?i)\.exe') {
        Write-Output "WARNING: EXE UninstallString for $VersionString - $($RegistryEntry.DisplayName)"
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

    Write-Output "WARNING: Non-MSI UninstallString for $VersionString - $uninstallString"
    $proc = Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c `"$uninstallString`" /quiet /norestart" `
        -Wait -PassThru -WindowStyle Hidden
    return $proc.ExitCode
}

$minimumVersions = Get-LatestVersions
foreach ($major in $supportedMajors) {
    Write-Output "Minimum v$major : $($minimumVersions[$major])"
}

$remediationFailed     = $false
$removed               = @()
$removedVersionStrings = @()
$skipped               = @()
$orphaned              = @()

$installedEntries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '^Microsoft ASP\.NET Core (\d+\.\d+\.\d+) Shared Framework' }

$allInstalledVersionStrings = @($installedEntries | ForEach-Object {
    $m = [regex]::Match($_.DisplayName, '(\d+\.\d+\.\d+)')
    if ($m.Success) { $m.Groups[1].Value }
})

foreach ($entry in $installedEntries) {
    $match = [regex]::Match($entry.DisplayName, '(\d+\.\d+\.\d+)')
    if (-not $match.Success) { continue }

    $versionString = $match.Groups[1].Value
    $archTag       = Get-ArchTagSuffix $entry.DisplayName

    try {
        $v     = [Version]$versionString
        $major = $v.Major

        $shouldRemove = $false
        $reasonTag    = ""

        if ($major -in $eolMajors) {
            $shouldRemove = $true
            $reasonTag    = "EOL$archTag"
        } elseif ($major -in $supportedMajors) {
            $minVersion = $minimumVersions[$major]

            if ($v -ge $minVersion) {
                Write-Output "CURRENT: $versionString$archTag - no action needed"
                continue
            }

            $minimumPresent = $allInstalledVersionStrings | Where-Object {
                try { ([Version]$_).Major -eq $major -and [Version]$_ -ge $minVersion } catch { $false }
            }

            if ($minimumPresent) {
                $shouldRemove = $true
                $reasonTag    = "outdated$archTag"
            } else {
                Write-Output "SKIPPING: $versionString$archTag - minimum $minVersion not yet deployed"
                $skipped += "$versionString$archTag(min:$minVersion not yet deployed)"
                $remediationFailed = $true
                continue
            }
        } else {
            continue
        }

        if ($shouldRemove) {
            Write-Output "Uninstalling ($reasonTag): $versionString via $($entry.PSChildName)"
            $exitCode = Uninstall-AspNetCoreRuntime -RegistryEntry $entry -VersionString $versionString

            if ($exitCode -eq 0 -or $exitCode -eq 3010) {
                Write-Output "SUCCESS (exit $exitCode): $versionString$archTag"
                $removed += "$versionString($reasonTag)"
                if ($removedVersionStrings -notcontains $versionString) {
                    $removedVersionStrings += $versionString
                }
            } else {
                Write-Output "FAILED (exit $exitCode): $versionString$archTag"
                $skipped += "$versionString$archTag(msiexec exit $exitCode)"
                $remediationFailed = $true
            }
        }

    } catch {
        Write-Output "ERROR processing $versionString$archTag`: $_"
        $remediationFailed = $true
    }
}

# --- Orphan check: folders on disk with no matching registry entry ---
$registeredVersionsFresh = Get-RegisteredVersionStrings
$diskVersions = @()
if (Test-Path $runtimePath) {
    $diskVersions = @(Get-ChildItem -Path $runtimePath -Directory | ForEach-Object { $_.Name })
}

if (Test-Path $runtimePath) {
    Get-ChildItem -Path $runtimePath -Directory | ForEach-Object {
        $folderVersion = $_.Name
        if ($folderVersion -in $registeredVersionsFresh) { return }
        if ($folderVersion -in $removedVersionStrings) {
            Write-Output "PENDING: $folderVersion - uninstalled via msiexec this run; folder cleanup deferred"
            return
        }

        try {
            $v     = [Version]$folderVersion
            $major = $v.Major

            if ($major -in $eolMajors) {
                Write-Output "ORPHAN (no registry entry) removing folder: $($_.FullName)"
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
                $orphaned += "$folderVersion(orphan-removed)"
            } elseif ($major -in $supportedMajors -and $v -lt $minimumVersions[$major]) {
                $minVersion = $minimumVersions[$major]

                if (Test-MinimumPresentForMajor -Major $major -MinVersion $minVersion -RegisteredVersions $registeredVersionsFresh -DiskVersions $diskVersions) {
                    Write-Output "ORPHAN (no registry entry) removing folder: $($_.FullName)"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
                    $orphaned += "$folderVersion(orphan-removed)"
                } else {
                    Write-Output "SKIPPING orphan: $folderVersion - minimum $minVersion not yet deployed"
                    $skipped += "$folderVersion(orphan-min:$minVersion not yet deployed)"
                    $remediationFailed = $true
                }
            }
        } catch {
            Write-Output "ERROR removing orphan folder $folderVersion`: $_"
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
