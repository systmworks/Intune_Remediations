<########################################################
    Name:       PS_Delete_EFI_Fonts_DETECT.ps1
    Purpose:    Detect font files in EFI partition.  These can be safely deleted, and save around 17 MB of space.
    Location:   Intune
    Owner:      Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        25/07/2025 - v1.0 - New Script developed
        
########################################################>

Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Delete_EFI_Fonts_DETECT.log" # -Append


# Check if system disk is MBR - if so exit the script
Get-Disk | Update-Disk
$disk = Get-Disk | Where-Object { $_.IsSystem -eq $true -and $_.PartitionStyle -eq 'MBR' }

if ($disk) {
    Write-Host "System disk is MBR. EFI partition check not required."
    Stop-Transcript | Out-Null
    Exit 0
}


# Calculate how much free space in EFI partition
$volInfo = Get-Volume -UniqueId "\\?\Volume$(((Get-Partition).Where{$_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'}.Guid))\"
$freeSpace = [math]::Round(($volInfo.SizeRemaining / 1MB), 0)


# Mount EFI partition to K: drive
MountVol K: /s

# Check for existence of .ttf files in the Fonts folder
$fontFiles = Get-ChildItem -Path "K:\EFI\Microsoft\Boot\Fonts\*.ttf" -Force -ErrorAction SilentlyContinue

# Remove K drive mapping
MountVol K: /d

# Exit with code 1 if any TTF files are found, 0 otherwise
if ($fontFiles) {
    Write-Host "TTF files found in EFI Fonts folder.  $freeSpace MB free in EFI partition."
    Stop-Transcript | Out-Null
    exit 1
} else {
    Write-Host "No TTF files found in EFI Fonts folder.  $freeSpace MB free in EFI partition."
    Stop-Transcript | Out-Null
    exit 0
}
