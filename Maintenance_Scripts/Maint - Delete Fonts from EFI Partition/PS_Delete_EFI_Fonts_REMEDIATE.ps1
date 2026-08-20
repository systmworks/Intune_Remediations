<########################################################
    Name:       PS_Delete_EFI_Fonts_REMEDIATE.ps1
    Purpose:    Delete fonts from EFI partition
    Location:   Intune
    Owner:      Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        25/07/2024 - v1.0 - New Script developed
        
########################################################>

Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Delete_EFI_Fonts_REMEDIATE.log" -Append


# Mount EFI partition to K: drive
MountVol K: /s

# Delete all .ttf font files in the EFI Microsoft Boot Fonts directory
$fontFiles = Get-ChildItem -Path "K:\EFI\Microsoft\Boot\Fonts\*.ttf" -Force -ErrorAction SilentlyContinue
foreach ($file in $fontFiles) {
    Write-Host "Deleting: $($file.FullName)"
    Remove-Item $file.FullName -Force
}

# Remove K drive mapping
MountVol K: /d


Stop-Transcript | Out-Null
