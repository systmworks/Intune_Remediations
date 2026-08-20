<########################################################
    Name:       PS_Adobe_CC_Auto_Updates_REMEDIATE.ps1
    Purpose:    Enable Creative Cloud Desktop and CC managed app auto-update settings
    Location:   Intune
    Owner:      Darren Milne
    Comments:   Runs as SYSTEM; end users cannot run PowerShell on this tenant.
                Per-user prefs under AppData\Local\Adobe\OOBE are enumerated via
                Win32_UserProfile. Stops Creative Cloud Desktop only when fixable
                prefs exist. Changes may not take effect until Creative Cloud next
                launches. Never creates missing prefs files. Fail-safe: no write unless
                structure is recognised and pre-write validation passes.
                Intune re-runs DETECT after remediation — this script reports operational
                success/failure only, not compliance. Classification helpers duplicated
                from DETECT; keep both files in sync when changing prefs logic.
                Acrobat and Reader are updated by PatchMyPC (out of scope);
                autoUpdateEnabled is a global CC switch and may also touch Acrobat (APRO).

                Exit 0 = All repair attempts succeeded (DETECT verifies compliance)
                Exit 1 = Operational failure (write error, process stop, unfixable structure)

    CHANGELOG:  (dd/mm/yyyy)
        03/08/2026 - v1.0 - New Script developed
        03/08/2026 - v1.0.1 - Exclude default.apps prefs stub from remediation target set
        03/08/2026 - v1.0.2 - Single-pass classification; slim operational output (DETECT re-runs for compliance)
        04/08/2026 - v1.0.3 - Repair-* log lines use Write-Host so return status is not polluted by output stream
        
########################################################>

$logPath = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Adobe_CC_Auto_Updates_REMEDIATE.log'
$logDir  = Split-Path -Parent $logPath
Start-Transcript -Path $logPath -Append -Force

$remediationFailed = $false
$remediationNotes  = [System.Collections.Generic.List[string]]::new()

try {
    # -------------------------------------------------------
    # SHARED - keep in sync with DETECT script
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
                State          = 'Unfixable'
                Detail         = 'file absent'
                CurrentValue   = $null
                ModifiedSource = $null
            }
        }

        try {
            $raw = Get-Content -LiteralPath $FilePath -Raw -ErrorAction Stop
            $xml = [xml]$raw
        } catch {
            return [PSCustomObject]@{
                State          = 'Unfixable'
                Detail         = "unreadable or not well-formed XML: $($_.Exception.Message)"
                CurrentValue   = $null
                ModifiedSource = $null
            }
        }

        $blobNode = $xml.SelectSingleNode("/prefs/property[@key='Apps_Panel_Pref']")
        if (-not $blobNode) {
            return [PSCustomObject]@{
                State          = 'Unfixable'
                Detail         = 'Apps_Panel_Pref property absent'
                CurrentValue   = $null
                ModifiedSource = $null
            }
        }

        try {
            $inner = [xml]$blobNode.InnerText
        } catch {
            return [PSCustomObject]@{
                State          = 'Unfixable'
                Detail         = "Apps_Panel_Pref blob not well-formed XML: $($_.Exception.Message)"
                CurrentValue   = $null
                ModifiedSource = $null
            }
        }

        if (-not $inner.SelectSingleNode('//autoUpdatePreferences')) {
            return [PSCustomObject]@{
                State          = 'Unfixable'
                Detail         = 'autoUpdatePreferences block absent'
                CurrentValue   = $null
                ModifiedSource = $null
            }
        }

        $enabledNode = $inner.SelectSingleNode('//autoUpdatePreferences/autoUpdateEnabled')
        $sourceNode  = $inner.SelectSingleNode('//autoUpdatePreferences/autoUpdateModifiedSource')
        $sourceValue = if ($sourceNode) { $sourceNode.InnerText.Trim() } else { $null }

        if (-not $enabledNode) {
            return [PSCustomObject]@{
                State          = 'Fixable'
                Detail         = 'autoUpdateEnabled absent'
                CurrentValue   = $null
                ModifiedSource = $sourceValue
            }
        }

        $value = $enabledNode.InnerText.Trim()
        if ($value -ieq 'true') {
            return [PSCustomObject]@{
                State          = 'Compliant'
                Detail         = 'autoUpdateEnabled=true'
                CurrentValue   = $value
                ModifiedSource = $sourceValue
            }
        }

        return [PSCustomObject]@{
            State          = 'Fixable'
            Detail         = "autoUpdateEnabled=$value"
            CurrentValue   = $value
            ModifiedSource = $sourceValue
        }
    }

    function Get-AdobePrefsTargets {
        param([string[]]$UserProfilePaths)

        $targets = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($userProfilePath in $UserProfilePaths) {
            $userName = Split-Path -Leaf $userProfilePath
            $oobePath = Join-Path $userProfilePath 'AppData\Local\Adobe\OOBE'
            if (-not (Test-Path -LiteralPath $oobePath)) { continue }

            $containerPrefs = Join-Path $oobePath 'com.adobe.acc.container.default.prefs'
            if (Test-Path -LiteralPath $containerPrefs) {
                $targets.Add([PSCustomObject]@{
                    UserName   = $userName
                    FilePath   = $containerPrefs
                    TargetType = 'container'
                    Label      = 'container'
                    State      = Get-ContainerAutoUpdateState -FilePath $containerPrefs
                })
            }

            foreach ($appsFile in Get-AdobeAppsPrefsFiles -OobePath $oobePath) {
                $targets.Add([PSCustomObject]@{
                    UserName   = $userName
                    FilePath   = $appsFile.FullName
                    TargetType = 'apps'
                    Label      = $appsFile.Name
                    State      = Get-AppsAutoUpdateState -FilePath $appsFile.FullName
                })
            }
        }

        return $targets
    }

    function Read-TextPreservingEncoding {
        param([string]$FilePath)

        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $encoding = New-Object System.Text.UTF8Encoding($hasBom)

        return [PSCustomObject]@{
            Text   = $encoding.GetString($bytes)
            HasBom = $hasBom
        }
    }

    function Write-TextPreservingEncoding {
        param(
            [string]$FilePath,
            [string]$Text,
            [bool]$HasBom
        )

        $encoding = New-Object System.Text.UTF8Encoding($HasBom)
        [System.IO.File]::WriteAllText($FilePath, $Text, $encoding)
    }

    function Backup-AdobePrefsFile {
        param(
            [string]$FilePath,
            [string]$UserName
        )

        $stamp = Get-Date -Format 'yyyyMMddHHmmss'
        $name  = Split-Path -Leaf $FilePath
        $dest  = Join-Path $logDir "${stamp}_${UserName}_${name}.bak"

        Copy-Item -LiteralPath $FilePath -Destination $dest -Force -ErrorAction Stop
        Write-Host "    Backup: $dest"
    }

    function Test-ContainerPrefsContent {
        param([string]$Text)

        $xml = [xml]$Text
        $node = $xml.SelectSingleNode("/prefs/property[@key='keepAppAlwaysUpToDate']")
        if (-not $node) { return $false }
        return ($node.InnerText.Trim() -ieq 'ON')
    }

    function Test-AppsPrefsContent {
        param([string]$Text)

        $xml = [xml]$Text
        $blobNode = $xml.SelectSingleNode("/prefs/property[@key='Apps_Panel_Pref']")
        if (-not $blobNode) { return $false }

        $inner = [xml]$blobNode.InnerText
        $enabledNode = $inner.SelectSingleNode('//autoUpdatePreferences/autoUpdateEnabled')
        if (-not $enabledNode) { return $false }

        return ($enabledNode.InnerText.Trim() -ieq 'true')
    }

    function Repair-ContainerPrefs {
        param(
            [string]$FilePath,
            [string]$UserName,
            [PSCustomObject]$State
        )

        switch ($State.State) {
            'Compliant' {
                Write-Host "    [OK] container already set ($($State.Detail))"
                return 'Skipped'
            }
            'Unfixable' {
                Write-Host "    [SKIP] container unfixable: $($State.Detail)"
                if ($State.Detail -ne 'file absent') {
                    $script:remediationFailed = $true
                    $script:remediationNotes.Add("[$UserName] container unfixable: $($State.Detail)")
                    return 'Failed'
                }
                return 'Skipped'
            }
        }

        try {
            $fileInfo = Read-TextPreservingEncoding -FilePath $FilePath
            $text = $fileInfo.Text
            $originalText = $text

            if ($State.CurrentValue) {
                $pattern = '(?s)(<property\s+key="keepAppAlwaysUpToDate">)[^<]*(</property>)'
                if ($text -notmatch $pattern) {
                    throw 'keepAppAlwaysUpToDate property pattern not found for replacement'
                }
                $text = [regex]::Replace($text, $pattern, '${1}ON${2}', 1)
            } else {
                $lineEnding = if ($text -match "`r`n") { "`r`n" } else { "`n" }
                $insertLine = "`t<property key=`"keepAppAlwaysUpToDate`">ON</property>$lineEnding"
                if ($text -notmatch '(?s)</prefs>') {
                    throw '</prefs> anchor not found for insertion'
                }
                $text = [regex]::Replace($text, '(?s)</prefs>', "$insertLine</prefs>", 1)
            }

            if ($text -eq $originalText) {
                throw 'no byte change produced'
            }

            if (-not (Test-ContainerPrefsContent -Text $text)) {
                throw 'pre-write validation failed for container prefs'
            }

            Backup-AdobePrefsFile -FilePath $FilePath -UserName $UserName
            Write-TextPreservingEncoding -FilePath $FilePath -Text $text -HasBom $fileInfo.HasBom
            Write-Host "    [SET] container keepAppAlwaysUpToDate=ON -> $FilePath"
            return 'Changed'

        } catch {
            Write-Host "    [FAIL] container $($FilePath): $_"
            $script:remediationFailed = $true
            $script:remediationNotes.Add("[$UserName] container failed: $_")
            return 'Failed'
        }
    }

    function Repair-AppsPrefs {
        param(
            [string]$FilePath,
            [string]$UserName,
            [PSCustomObject]$State
        )

        switch ($State.State) {
            'Compliant' {
                Write-Host "    [OK] apps already set ($($State.Detail))"
                return 'Skipped'
            }
            'Unfixable' {
                Write-Host "    [SKIP] apps unfixable: $($State.Detail)"
                if ($State.Detail -ne 'file absent') {
                    $script:remediationFailed = $true
                    $script:remediationNotes.Add("[$UserName] apps unfixable: $($State.Detail)")
                    return 'Failed'
                }
                return 'Skipped'
            }
        }

        try {
            $fileInfo = Read-TextPreservingEncoding -FilePath $FilePath
            $text = $fileInfo.Text
            $originalText = $text

            $needsEnabledFix = -not ($State.CurrentValue -and $State.CurrentValue -ieq 'true')
            $needsSourceInsert = [string]::IsNullOrWhiteSpace($State.ModifiedSource)

            if ($needsEnabledFix) {
                if ($State.CurrentValue) {
                    $escapedPattern = '&lt;autoUpdateEnabled&gt;[^&]*&lt;/autoUpdateEnabled&gt;'
                    $unescapedPattern = '<autoUpdateEnabled>[^<]*</autoUpdateEnabled>'

                    if ($text -match $escapedPattern) {
                        $replacement = '&lt;autoUpdateEnabled&gt;true&lt;/autoUpdateEnabled&gt;'
                        if ($needsSourceInsert) {
                            $replacement += '&lt;autoUpdateModifiedSource&gt;user-action&lt;/autoUpdateModifiedSource&gt;'
                        }
                        $text = [regex]::Replace($text, $escapedPattern, $replacement, 1)
                    } elseif ($text -match $unescapedPattern) {
                        $replacement = '<autoUpdateEnabled>true</autoUpdateEnabled>'
                        if ($needsSourceInsert) {
                            $replacement += '<autoUpdateModifiedSource>user-action</autoUpdateModifiedSource>'
                        }
                        $text = [regex]::Replace($text, $unescapedPattern, $replacement, 1)
                    } else {
                        throw 'autoUpdateEnabled element pattern not found for replacement'
                    }
                } else {
                    if ($text -notmatch '&lt;autoUpdatePreferences&gt;') {
                        throw 'autoUpdatePreferences anchor not found for insertion'
                    }

                    $insertBlock = '&lt;autoUpdateEnabled&gt;true&lt;/autoUpdateEnabled&gt;'
                    if ($needsSourceInsert) {
                        $insertBlock += '&lt;autoUpdateModifiedSource&gt;user-action&lt;/autoUpdateModifiedSource&gt;'
                    }

                    $text = [regex]::Replace($text, '&lt;autoUpdatePreferences&gt;', "&lt;autoUpdatePreferences&gt;$insertBlock", 1)
                }
            } elseif ($needsSourceInsert) {
                if ($text -match '&lt;autoUpdateEnabled&gt;true&lt;/autoUpdateEnabled&gt;') {
                    $text = [regex]::Replace(
                        $text,
                        '&lt;autoUpdateEnabled&gt;true&lt;/autoUpdateEnabled&gt;',
                        '&lt;autoUpdateEnabled&gt;true&lt;/autoUpdateEnabled&gt;&lt;autoUpdateModifiedSource&gt;user-action&lt;/autoUpdateModifiedSource&gt;',
                        1
                    )
                } elseif ($text -match '<autoUpdateEnabled>true</autoUpdateEnabled>') {
                    $text = [regex]::Replace(
                        $text,
                        '<autoUpdateEnabled>true</autoUpdateEnabled>',
                        '<autoUpdateEnabled>true</autoUpdateEnabled><autoUpdateModifiedSource>user-action</autoUpdateModifiedSource>',
                        1
                    )
                } else {
                    throw 'autoUpdateEnabled=true anchor not found for source insertion'
                }
            }

            if ($text -eq $originalText) {
                throw 'no byte change produced'
            }

            if (-not (Test-AppsPrefsContent -Text $text)) {
                throw 'pre-write validation failed for apps prefs'
            }

            Backup-AdobePrefsFile -FilePath $FilePath -UserName $UserName
            Write-TextPreservingEncoding -FilePath $FilePath -Text $text -HasBom $fileInfo.HasBom
            Write-Host "    [SET] apps autoUpdateEnabled=true -> $FilePath"
            if ($State.ModifiedSource) {
                Write-Host "    [INFO] preserved existing autoUpdateModifiedSource=$($State.ModifiedSource)"
            } elseif ($needsSourceInsert) {
                Write-Host '    [SET] apps autoUpdateModifiedSource=user-action inserted'
            }
            return 'Changed'

        } catch {
            Write-Host "    [FAIL] apps $($FilePath): $_"
            $script:remediationFailed = $true
            $script:remediationNotes.Add("[$UserName] apps failed: $_")
            return 'Failed'
        }
    }

    function Stop-CreativeCloudDesktop {
        $ccProcessNames = @(
            'Creative Cloud'
            'CCXProcess'
            'CCLibrary'
            'Adobe Desktop Service'
        )

        Write-Output '[*] Stopping Creative Cloud Desktop processes...'
        foreach ($procName in $ccProcessNames) {
            $procs = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($procs.Count -eq 0) { continue }

            foreach ($proc in $procs) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }

            Start-Sleep -Milliseconds 500
            $remaining = @(Get-Process -Name $procName -ErrorAction SilentlyContinue)
            if ($remaining.Count -eq 0) {
                Write-Output "    Stopped: $procName"
            } else {
                Write-Output "    WARNING: $procName still running ($($remaining.Count) process(es))"
                $script:remediationFailed = $true
                $script:remediationNotes.Add("Could not stop $procName")
            }
        }

        Start-Sleep -Seconds 3
    }

    # -------------------------------------------------------
    # MAIN
    # -------------------------------------------------------

    $userProfilePaths = @(Get-AdobeUserProfilePaths)
    $targets          = @(Get-AdobePrefsTargets -UserProfilePaths $userProfilePaths)
    $needsFix         = @($targets | Where-Object { $_.State.State -eq 'Fixable' })

    if ($needsFix.Count -gt 0) {
        Stop-CreativeCloudDesktop
    } else {
        Write-Output '[*] No fixable Adobe CC auto-update prefs found; skipping process stop.'
    }

    $changed = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    $failed  = [System.Collections.Generic.List[string]]::new()

    foreach ($userProfilePath in $userProfilePaths) {
        $userName = Split-Path -Leaf $userProfilePath
        $oobePath = Join-Path $userProfilePath 'AppData\Local\Adobe\OOBE'
        if (-not (Test-Path -LiteralPath $oobePath)) { continue }

        $userTargets = @($targets | Where-Object { $_.UserName -eq $userName })
        Write-Output "`n[USER] $userName"

        if ($userTargets.Count -eq 0) {
            Write-Output '    [SKIP] No Adobe CC prefs files present in OOBE.'
            $skipped.Add("[$userName] no prefs files")
            continue
        }

        $hasContainer = $false
        $hasApps      = $false

        foreach ($target in $userTargets) {
            if ($target.TargetType -eq 'container') { $hasContainer = $true }
            if ($target.TargetType -eq 'apps') { $hasApps = $true }

            $result = if ($target.TargetType -eq 'container') {
                Repair-ContainerPrefs -FilePath $target.FilePath -UserName $userName -State $target.State
            } else {
                Repair-AppsPrefs -FilePath $target.FilePath -UserName $userName -State $target.State
            }

            $entry = "[$userName] $($target.Label)"
            switch ($result) {
                'Changed' { $changed.Add($entry) }
                'Skipped' { $skipped.Add($entry) }
                'Failed'  { $failed.Add($entry) }
                default   { throw "Unexpected repair result: $result" }
            }
        }

        if (-not $hasContainer) {
            Write-Output '    [SKIP] com.adobe.acc.container.default.prefs not present.'
            $skipped.Add("[$userName] container file absent")
        }
        if (-not $hasApps) {
            Write-Output '    [SKIP] No com.adobe.accc.apps.*.prefs present.'
            $skipped.Add("[$userName] apps prefs absent")
        }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($changed.Count -gt 0) { $parts.Add("Changed: $($changed -join ' | ')") }
    if ($skipped.Count -gt 0) { $parts.Add("Skipped: $($skipped -join ' | ')") }
    if ($failed.Count -gt 0)  { $parts.Add("Failed: $($failed -join ' | ')") }
    if ($remediationNotes.Count -gt 0) { $parts.Add("Notes: $($remediationNotes -join ' | ')") }
    if ($parts.Count -eq 0) { $parts.Add('Nothing to remediate') }

    $outputLine = if ($remediationFailed) {
        "FAILED: $($parts -join ' -- ')"
    } else {
        "OK: $($parts -join ' -- ')"
    }

    Write-Output $outputLine

    if ($remediationFailed) {
        exit 1
    }

    exit 0

} catch {
    Write-Output "ERROR: Remediation failed: $_"
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
