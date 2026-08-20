<########################################################
    Name:       PS_Delete_EFI_Firmware_BIN_File_DETECT.ps1
    Purpose:    To detect HP firmware.bin update file in EFI partition.
                If its larger than 20 MB and older than 7 days, trigger remediation script to delete.
    Location:   Intune
    Owner:      Darren Milne
    Comments:  

    CHANGELOG:  (dd/mm/yyyy)
        23/09/2024 - v1.0 - New Script developed
        25/09/2024 - v1.1 - Added free space in EFI partition to end of text output
        26/09/2024 - v1.2 - Mount EFI partition using MountVol instead of Diskpart
        01/05/2025 - v1.3 - Changed time from 30 days to 7 days
        
########################################################>

Start-Transcript -Path "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PS_Delete_EFI_Firmware_BIN_File_DETECT.log" # -Append


# set age of the file before able to delete - to allow time for the device to reboot and update apply
$days = 7

# Calculate how much free space in EFI partition
$volInfo = Get-Volume -UniqueId "\\?\Volume$(((Get-Partition).Where{$_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'}.Guid))\"
$freeSpace = [math]::Round(($volInfo.SizeRemaining / 1MB), 0)

# Mount EFI partition to K: drive
MountVol K: /s

# Step 2: Check if the file K:\EFI\HP\DEVFW\firmware.bin exists
$firmwareFilePath = "K:\EFI\HP\DEVFW\firmware.bin"

if (Test-Path $firmwareFilePath) {
    # Get file details
    $fileInfo = Get-Item $firmwareFilePath
    $fileSizeMB = [math]::round($fileInfo.Length / 1MB, 0)
    $lastModifiedDate = $fileInfo.LastWriteTime    # cant convert to string until after calc daysOld
    $daysOld = ( (Get-Date) - $lastModifiedDate)
    $lastModifiedDateAU = $fileInfo.LastWriteTime.ToString("dd-MM-yyyy")

    # Remove K drive mapping
    MountVol K: /d

    # Check if the file is larger than 20 MB and older than 7 days
    if ($fileSizeMB -gt 20 -and $daysOld.Days -gt $days) {
        # Output the file details if conditions ARE met
        Write-Host "Warn - Can delete file: " -NoNewLine -ForegroundColor Red
        Write-Host "Path: $firmwareFilePath | " -NoNewLine
        Write-Host "Size: $fileSizeMB MB | " -NoNewLine
        Write-Host "Last Modified: $lastModifiedDateAU | " -NoNewLine
        Write-Host "Free space in EFI partition = [$freeSpace] MB"
        Stop-Transcript | Out-Null
        Exit 1
    } else {
        # Output the file details if conditions are NOT met
        Write-Host "Do not delete file:  " -NoNewLine -ForegroundColor Green
        Write-Host "Path: $firmwareFilePath | " -NoNewLine
        Write-Host "Size: $fileSizeMB MB | " -NoNewLine
        Write-Host "Last Modified: $lastModifiedDateAU | " -NoNewLine
        Write-Host "Free space in EFI partition = [$freeSpace] MB"
        Stop-Transcript | Out-Null
        Exit 0
    }
} else {
    # Remove K drive mapping
    MountVol K: /d

    Write-Host "File does not exist: $firmwareFilePath | " -NoNewLine -ForegroundColor Green
    Write-Host "Free space in EFI partition = [$freeSpace] MB"
    Stop-Transcript | Out-Null
    Exit 0
}
