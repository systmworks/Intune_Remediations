<########################################################
    Name:       PS_Adobe_CC_Auto_Updates_DETECT.ps1
    Purpose:    Detect Creative Cloud Desktop and CC managed app auto-update settings
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Runs as SYSTEM; end users cannot run PowerShell on this tenant.
                Per-user prefs under AppData\Local\Adobe\OOBE are enumerated via
                Win32_UserProfile. Changes may not take effect until Creative Cloud
                next launches. Classification helpers duplicated from REMEDIATE;
                keep both files in sync when changing prefs logic.
                Acrobat and Reader are updated by PatchMyPC (out of scope);
                autoUpdateEnabled is a global CC switch and may also touch Acrobat (APRO).

                Exit 0 = Compliant, or unfixable items reported as REVIEW (no remediation loop)
                Exit 1 = Fixable non-compliance (remediation can act)

    CHANGELOG:  (dd/mm/yyyy)
        03/08/2026 - v1.0 - New Script developed
        03/08/2026 - v1.0.1 - Report Adobe CC Not Found when not installed; exclude default.apps prefs stub
        03/08/2026 - v1.0.2 - Deduplicate CC install probe; fix policy diagnostic paths; output cap
        04/08/2026 - v1.0.3 - Transcript log overwrites each run (no -Append)
        
########################################################>

$logPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Adobe_CC_Auto_Updates_DETECT.log'
Start-Transcript -Path $logPath -Force

try {
    # -------------------------------------------------------
    # SHARED - keep in sync with REMEDIATE script
    # -------------------------------------------------------

    function Get-AdobeUserProfilePaths {
        Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Special -and $_.LocalPath } |
            ForEach-Object { $_.LocalPath }
    }

    function Get-AdobeAppsPrefsFiles {
        param([string]$OobePath)

        Get-ChildItem -Path $OobePath -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^com\.adobe\.accc\.apps\.[0-9A-F]+\.prefs$' }
    }

    function Get-AdobeCreativeCloudInfo {
        $ccdPaths = @(
            "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe"
            "${env:ProgramFiles(x86)}\Adobe\Adobe Creative Cloud\ACC\Creative Cloud UI Helper.exe"
            "$env:ProgramFiles\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe"
        )

        foreach ($path in $ccdPaths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            $ver = (Get-Item -LiteralPath $path).VersionInfo.ProductVersion
            return [PSCustomObject]@{
                Installed = $true
                ExePath   = $path
                Version   = $ver
            }
        }

        $uninstallKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
        $entries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match 'Adobe Creative Cloud' -and
                $_.DisplayName -notmatch 'Uninstall'
            }

        if ($entries) {
            return [PSCustomObject]@{
                Installed = $true
                ExePath   = $null
                Version   = $null
            }
        }

        return [PSCustomObject]@{
            Installed = $false
            ExePath   = $null
            Version   = $null
        }
    }

    function Get-ContainerAutoUpdateState {
        param([string]$FilePath)

        if (-not (Test-Path -LiteralPath $FilePath)) {
            return [PSCustomObject]@{
                State        = 'Unfixable'
                Detail       = 'file absent'
                CurrentValue = $null
            }
        }

        try {
            $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
            $xml = [xml]$raw
        } catch {
            return [PSCustomObject]@{
                State        = 'Unfixable'
                Detail       = "unreadable or not well-formed XML: $($_.Exception.Message)"
                CurrentValue = $null
            }
        }

        $prefsNode = $xml.SelectSingleNode('/prefs')
        if (-not $prefsNode) {
            return [PSCustomObject]@{
                State        = 'Unfixable'
                Detail       = 'no /prefs root'
                CurrentValue = $null
            }
        }

        $node = $xml.SelectSingleNode("/prefs/property[@key='keepAppAlwaysUpToDate']")
        if (-not $node) {
            return [PSCustomObject]@{
                State        = 'Fixable'
                Detail       = 'keepAppAlwaysUpToDate absent'
                CurrentValue = $null
            }
        }

        $value = $node.InnerText.Trim()
        if ($value -ieq 'ON') {
            return [PSCustomObject]@{
                State        = 'Compliant'
                Detail       = 'keepAppAlwaysUpToDate=ON'
                CurrentValue = $value
            }
        }

        return [PSCustomObject]@{
            State        = 'Fixable'
            Detail       = "keepAppAlwaysUpToDate=$value"
            CurrentValue = $value
        }
    }

    function Get-AppsAutoUpdateState {
        param([string]$FilePath)

        if (-not (Test-Path -LiteralPath $FilePath)) {
            return [PSCustomObject]@{
                State              = 'Unfixable'
                Detail             = 'file absent'
                CurrentValue       = $null
                ModifiedSource     = $null
                ModifiedSourceNote = $null
            }
        }

        try {
            $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
            $xml = [xml]$raw
        } catch {
            return [PSCustomObject]@{
                State              = 'Unfixable'
                Detail             = "unreadable or not well-formed XML: $($_.Exception.Message)"
                CurrentValue       = $null
                ModifiedSource     = $null
                ModifiedSourceNote = $null
            }
        }

        $blobNode = $xml.SelectSingleNode("/prefs/property[@key='Apps_Panel_Pref']")
        if (-not $blobNode) {
            return [PSCustomObject]@{
                State              = 'Unfixable'
                Detail             = 'Apps_Panel_Pref property absent'
                CurrentValue       = $null
                ModifiedSource     = $null
                ModifiedSourceNote = $null
            }
        }

        try {
            $inner = [xml]$blobNode.InnerText
        } catch {
            return [PSCustomObject]@{
                State              = 'Unfixable'
                Detail             = "Apps_Panel_Pref blob not well-formed XML: $($_.Exception.Message)"
                CurrentValue       = $null
                ModifiedSource     = $null
                ModifiedSourceNote = $null
            }
        }

        if (-not $inner.SelectSingleNode('//autoUpdatePreferences')) {
            return [PSCustomObject]@{
                State              = 'Unfixable'
                Detail             = 'autoUpdatePreferences block absent'
                CurrentValue       = $null
                ModifiedSource     = $null
                ModifiedSourceNote = $null
            }
        }

        $enabledNode = $inner.SelectSingleNode('//autoUpdatePreferences/autoUpdateEnabled')
        $sourceNode  = $inner.SelectSingleNode('//autoUpdatePreferences/autoUpdateModifiedSource')
        $sourceValue = if ($sourceNode) { $sourceNode.InnerText.Trim() } else { $null }
        $sourceNote  = if ($sourceValue) { "autoUpdateModifiedSource=$sourceValue" } else { 'autoUpdateModifiedSource absent' }

        if (-not $enabledNode) {
            return [PSCustomObject]@{
                State              = 'Fixable'
                Detail             = 'autoUpdateEnabled absent'
                CurrentValue       = $null
                ModifiedSource     = $sourceValue
                ModifiedSourceNote = $sourceNote
            }
        }

        $value = $enabledNode.InnerText.Trim()
        if ($value -ieq 'true') {
            return [PSCustomObject]@{
                State              = 'Compliant'
                Detail             = 'autoUpdateEnabled=true'
                CurrentValue       = $value
                ModifiedSource     = $sourceValue
                ModifiedSourceNote = $sourceNote
            }
        }

        return [PSCustomObject]@{
            State              = 'Fixable'
            Detail             = "autoUpdateEnabled=$value"
            CurrentValue       = $value
            ModifiedSource     = $sourceValue
            ModifiedSourceNote = $sourceNote
        }
    }

    function Get-AdobeMachineDiagnostics {
        param([PSCustomObject]$CcInfo)

        $findings = [System.Collections.Generic.List[string]]::new()

        if ($CcInfo.Version) {
            $findings.Add("Creative Cloud Desktop version $($CcInfo.Version) ($($CcInfo.ExePath))")
        } elseif ($CcInfo.Installed -and -not $CcInfo.ExePath) {
            $findings.Add('Creative Cloud Desktop installed (registry only; exe path not found)')
        }

        $adminPrefsPaths = @(
            "${env:ProgramFiles(x86)}\Common Files\Adobe\AAMUpdaterInventory\1.0\AdobeUpdaterAdminPrefs.dat"
            "$env:ProgramFiles\Common Files\Adobe\AAMUpdaterInventory\1.0\AdobeUpdaterAdminPrefs.dat"
        )
        foreach ($path in $adminPrefsPaths) {
            if (Test-Path -LiteralPath $path) {
                $findings.Add("AdobeUpdaterAdminPrefs.dat present at $path")
            }
        }

        $serviceConfigPaths = @(
            "${env:ProgramFiles(x86)}\Common Files\Adobe\OOBE_Enterprise\ServiceConfig.xml"
            "$env:ProgramFiles\Common Files\Adobe\OOBE_Enterprise\ServiceConfig.xml"
        )
        foreach ($path in $serviceConfigPaths) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            try {
                $svc = [xml](Get-Content -LiteralPath $path -Raw -ErrorAction Stop)
                $updatesAllowed = $svc.SelectSingleNode('//updatesAllowed')
                if ($updatesAllowed) {
                    $findings.Add("ServiceConfig.xml updatesAllowed=$($updatesAllowed.InnerText) at $path")
                } else {
                    $findings.Add("ServiceConfig.xml present at $path")
                }
            } catch {
                $findings.Add("ServiceConfig.xml present but unreadable at $path")
            }
        }

        $policyRoots = @(
            'HKLM:\SOFTWARE\Policies\Adobe'
            'HKLM:\SOFTWARE\WOW6432Node\Policies\Adobe'
        )
        foreach ($root in $policyRoots) {
            if (-not (Test-Path -LiteralPath $root)) { continue }
            Get-ChildItem -Path $root -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $keyPath = $_.PSPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
                    $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
                    if (-not $item) { return }
                    $item.PSObject.Properties |
                        Where-Object {
                            $_.Name -notmatch '^PS' -and
                            $_.Name -match 'update|Update|updater|Updater|disable|Disable|allow|Allow'
                        } |
                        ForEach-Object {
                            $findings.Add("Policy $keyPath $($_.Name)=$($_.Value)")
                        }
                }
        }

        if ($findings.Count -eq 0) {
            return @('No machine-level Adobe update diagnostics found')
        }

        return $findings
    }

    function Add-AdobeFinding {
        param(
            [string]$UserName,
            [string]$Label,
            [PSCustomObject]$State,
            [System.Collections.Generic.List[string]]$FixableFindings,
            [System.Collections.Generic.List[string]]$ReviewFindings,
            [string]$CompliantSuffix = ''
        )

        switch ($State.State) {
            'Fixable' {
                $FixableFindings.Add("[$UserName] ${Label}: $($State.Detail)")
            }
            'Unfixable' {
                if ($State.Detail -ne 'file absent') {
                    $ReviewFindings.Add("[$UserName] ${Label}: $($State.Detail)")
                }
            }
            'Compliant' {
                $suffix = if ($CompliantSuffix) { " ($CompliantSuffix)" } else { " ($($State.Detail))" }
                Write-Output "[$UserName] ${Label}: compliant$suffix"
            }
            default {
                throw "Unexpected state: $($State.State)"
            }
        }
    }

    function Format-FindingList {
        param(
            [System.Collections.Generic.List[string]]$Findings,
            [int]$MaxItems = 5
        )

        if ($Findings.Count -eq 0) { return '' }
        if ($Findings.Count -le $MaxItems) {
            return ($Findings -join ' | ')
        }

        $shown = ($Findings | Select-Object -First $MaxItems) -join ' | '
        $remaining = $Findings.Count - $MaxItems
        return "$shown | ... and $remaining more"
    }

    # -------------------------------------------------------
    # MAIN
    # -------------------------------------------------------

    $fixableFindings = [System.Collections.Generic.List[string]]::new()
    $reviewFindings  = [System.Collections.Generic.List[string]]::new()
    $anyOobeScanned  = $false
    $ccInfo          = Get-AdobeCreativeCloudInfo
    $machineDiag     = Get-AdobeMachineDiagnostics -CcInfo $ccInfo

    foreach ($machineItem in $machineDiag) {
        Write-Output "MACHINE: $machineItem"
    }

    foreach ($userProfilePath in @(Get-AdobeUserProfilePaths)) {
        $userName = Split-Path -Leaf $userProfilePath
        $oobePath = Join-Path $userProfilePath 'AppData\Local\Adobe\OOBE'

        if (-not (Test-Path -LiteralPath $oobePath)) { continue }

        $anyOobeScanned = $true

        $containerPrefs = Join-Path $oobePath 'com.adobe.acc.container.default.prefs'
        Add-AdobeFinding -UserName $userName -Label 'container' `
            -State (Get-ContainerAutoUpdateState -FilePath $containerPrefs) `
            -FixableFindings $fixableFindings -ReviewFindings $reviewFindings

        foreach ($appsPrefsFile in Get-AdobeAppsPrefsFiles -OobePath $oobePath) {
            $appsState = Get-AppsAutoUpdateState -FilePath $appsPrefsFile.FullName
            Add-AdobeFinding -UserName $userName -Label "apps/$($appsPrefsFile.Name)" `
                -State $appsState -FixableFindings $fixableFindings -ReviewFindings $reviewFindings `
                -CompliantSuffix "$($appsState.Detail); $($appsState.ModifiedSourceNote)"
        }
    }

    $outputParts = [System.Collections.Generic.List[string]]::new()

    if ($fixableFindings.Count -gt 0) {
        $outputParts.Add("NON-COMPLIANT: $(Format-FindingList -Findings $fixableFindings)")
    }

    if ($reviewFindings.Count -gt 0) {
        $outputParts.Add("REVIEW: $(Format-FindingList -Findings $reviewFindings)")
    }

    if ($outputParts.Count -eq 0) {
        if (-not $ccInfo.Installed -and -not $anyOobeScanned) {
            $outputParts.Add('Adobe CC Not Found: Creative Cloud Desktop is not installed and no user OOBE prefs were found.')
        } else {
            $outputParts.Add('COMPLIANT: All existing Adobe CC auto-update prefs are correctly set.')
        }
    }

    Write-Output ($outputParts -join ' -- ')

    if ($fixableFindings.Count -gt 0) {
        exit 1
    }

    exit 0

} catch {
    Write-Output "ERROR: Detection failed: $_"
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
