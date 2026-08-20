<########################################################
    Name:       PS_Unallocated_Disk_Space_DETECT.ps1
    Purpose:    Detect unallocated space on the disk hosting C:
    Location:   Intune
    Owner:      Darren Milne
    Comments:   

    CHANGELOG:  (dd/mm/yyyy)
        11/11/2024 - v1.0 - New Script developed
        20/07/2026 - v1.1 - Select disk via C: partition's DiskNumber instead of filtering by ProvisioningType,
                             so it works on VMs and multi-disk hosts.  Added try/catch.

########################################################>

Try {
    # Rescan disks
    Get-Disk | Update-Disk

    # Find the disk that actually hosts C:, and compare disk size vs partition size
    $cPartition = Get-Partition -DriveLetter C
    $disk       = Get-Disk -Number $cPartition.DiskNumber

    $diskSizeGB    = [int][Math]::Ceiling($disk.Size / 1gb)
    $currentSizeGB = [int][Math]::Ceiling($cPartition.Size / 1gb)

    # Calculate the difference (should be 1GB or less)
    $difGB = $diskSizeGB - $currentSizeGB

    # If Disk Size is more than 3GB larger than current C Partition size, flag the issue
    If ($difGB -gt 3) {
        Write-Host "$difGB GB variance ($currentSizeGB < $diskSizeGB GB)" -ForegroundColor Red
        Exit 1
    } Else {
        Write-Host "C: is maximum $currentSizeGB GB" -ForegroundColor Green
        Exit 0
    }
}
Catch {
    Write-Host "Script error: $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}
