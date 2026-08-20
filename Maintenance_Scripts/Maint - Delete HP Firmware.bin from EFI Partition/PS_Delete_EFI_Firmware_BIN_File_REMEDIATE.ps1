<########################################################
    Name:       PS_Delete_EFI_Firmware_BIN_File_REMEDIATE.ps1
    Purpose:    Delete HP firmware.bin update file in EFI partition
    Location:   Intune
    Owner:      Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        23/09/2024 - v1.0 - New Script developed
        26/09/2024 - v1.1 - Mount EFI partition using MountVol instead of Diskpart
        
########################################################>

Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Delete_EFI_Firmware_BIN_File_REMEDIATE.log" -Append


# Mount EFI partition to K: drive
MountVol K: /s

# Delete firmware BIN file
$firmwareFilePath = "K:\EFI\HP\DEVFW\firmware.bin"
Write-Host "Deleting: $firmwareFilePath"
Remove-Item $firmwareFilePath

# Remove K drive mapping
MountVol K: /d

Stop-Transcript | Out-Null
