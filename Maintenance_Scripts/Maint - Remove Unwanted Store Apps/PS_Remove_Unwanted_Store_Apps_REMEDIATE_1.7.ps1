<########################################################
    Name:      PS_Remove_Unwanted_Store_Apps_REMEDIATE_1.7.ps1
    Purpose:   Tries to remove a big list of unwanted Microsoft Store apps.
    Location:  Intune
    Owner:     Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        15/01/2025 - v1.4 - added Microsoft.Windows.DevHome
        21/01/2025 - v1.5 - added Microsoft.Copilot
        22/05/2026 - v1.6 - exclude Microsoft.MicrosoftOfficeHub (Microsoft 365 Copilot)
        13/08/2026 - v1.7 - added BingSearch, StartExperiences, WebExperience, GameAssist, CrossDevice; detect installed or provisioned

########################################################>

Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Remove_Unwanted_Store_Apps_REMEDIATE_1.7.log" # -Append

$ErrorActionPreference = 'Continue'

$apps = @(
    "*AdobeSystemsIncorporated.AdobePhotoshopExpress*",
    "*Clipchamp.Clipchamp*",
    "*Dolby*",
    "*Duolingo-LearnLanguagesforFree*",
    "*Facebook*",
    "*Flipboard*",
    "*HULULLC.HULUPLUS*",
    "*king.com.BubbleWitch3Saga*",
    "*king.com.CandyCrushSaga*",
    "*king.com.CandyCrushSodaSaga*",
    "*Microsoft.3DBuilder*",
    "*Microsoft.Asphalt8Airborne*",
    "*Microsoft.BingFinance*",
    "*Microsoft.BingNews*",
    "*Microsoft.BingSearch*",
    "*Microsoft.BingSports*",
    "*Microsoft.BingTranslator*",
    "*Microsoft.BingWeather*",
    "*Microsoft.Copilot*",    # added 21-1-2025
    "*Microsoft.Edge.GameAssist*",
    "*Microsoft.GamingApp*",
    "*Microsoft.GetHelp*",
    "*Microsoft.Getstarted*",
    "*Microsoft.Messaging*",
    "*Microsoft.Microsoft3DViewer*",
    "*Microsoft.MicrosoftSolitaireCollection*",
    "*Microsoft.MixedReality.Portal*",
    "*Microsoft.NetworkSpeedTest*",
    "*Microsoft.News*",
    "*Microsoft.Office.OneNote*",
    "*Microsoft.Office.Sway*",
    "*Microsoft.OneConnect*",
    "*Microsoft.People*",
    "*Microsoft.PowerAutomateDesktop*",
    "*Microsoft.Print3D*",
    "*Microsoft.RemoteDesktop*",
    "*Microsoft.SkypeApp*",
    "*Microsoft.StartExperiencesApp*",
    "*Microsoft.WindowsAlarms*",
    "*microsoft.windowscommunicationsapps*",
    "*Microsoft.WindowsFeedbackHub*",
    "*Microsoft.WindowsMaps*",
    "*Microsoft.WindowsSoundRecorder*",
    "*Microsoft.Windows.DevHome*",    # added 15-1-2025
    "*Microsoft.Xbox.TCUI*",
    "*Microsoft.XboxApp*",
    "*Microsoft.XboxGameOverlay*",
    "*Microsoft.XboxGamingOverlay*",
    "*Microsoft.XboxIdentityProvider*",
    "*Microsoft.XboxSpeechToTextOverlay*",
    "*Microsoft.YourPhone*",
    "*Microsoft.ZuneMusic*",
    "*Microsoft.ZuneVideo*",
    "*MicrosoftCorporationII.QuickAssist*",
    "*MicrosoftWindows.Client.WebExperience*",
    "*MicrosoftWindows.CrossDevice*",
    "*Netflix*",
    "*PandoraMediaInc*",
    "*PICSART-PHOTOSTUDIO*",
    "*Royal Revolt*",
    "*Speed Test*",
    "*Spotify*",
    "*Twitter*",
    "*Wunderlist*"    # no comma
)

# Apps Not Removed:
#   "*Microsoft.549981C3F5F10*",
#   "*Microsoft.MicrosoftOfficeHub*",
#   "*Microsoft.Windows.ParentalControls*",
#   "*Microsoft.MicrosoftStickyNotes*",
#   "*Microsoft.MSPaint*",
#   "*Microsoft.ScreenSketch*",
#   "*Microsoft.Todos*",
#   "*Microsoft.Windows.Photos*",
#   "*Microsoft.WindowsCalculator*",
#   "*Microsoft.WindowsCamera*",
#   "Microsoft.DesktopAppInstaller",
#   "Microsoft.HEIFImageExtension"

try {
    $provisioned = Get-AppxProvisionedPackage -Online
}
catch {
    $errMsg = $_.Exception.Message
    Write-Host "Remediate error: $errMsg" -NoNewLine
    Stop-Transcript | Out-Null
    exit 1
}

foreach ($app in $apps) {
    $pkg = Get-AppxPackage -Name $app -AllUsers
    $prov = @($provisioned | Where-Object { $_.DisplayName -like $app })

    if (-not $pkg -and -not $prov) {
        continue
    }

    Write-Host "Attempting to remove $app"

    if ($pkg) {
        try {
            $pkg | Remove-AppxPackage -AllUsers -ErrorAction Continue
        }
        catch {
            Write-Host "Failed to remove installed package for ${app}: $($_.Exception.Message)"
        }
    }

    foreach ($p in $prov) {
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Continue
        }
        catch {
            Write-Host "Failed to remove provisioned package for ${app}: $($_.Exception.Message)"
        }
    }
}

Write-Host "Remediation complete" -NoNewLine
Stop-Transcript | Out-Null
exit 0
