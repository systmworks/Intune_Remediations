<########################################################
    Name:       PS_Unallocated_Disk_Space_REMEDIATE.ps1
    Purpose:    Remove a blocking partition after C: (if present) and
                extend C: to consume unallocated space
    Location:   Intune
    Owner:      Darren Milne
    Comments:   

    CHANGELOG:  (dd/mm/yyyy)
        Original  - v1.0 - Deleted any partition with Type -eq 'Unknown',
                            then extended C:. Worked on legacy MBR Win10
                            VMs but Type -eq 'Unknown' is not a reliable
                            way to identify the recovery partition on
                            GPT/Win11 - it's a catch-all for any
                            unrecognized partition type, not specifically
                            the one blocking C:.
        20/07/2026 - v1.1 - Only removes a partition if it is provably
                             the blocker: same disk as C:, positioned
                             after C:, small (<=1GB), and NOT the EFI
                             System or Microsoft Reserved partition.
                             Added try/catch and skip-if-not-needed logic.
        
########################################################>

Try {
    Get-Disk | Update-Disk

    $cPartition = Get-Partition -DriveLetter C
    $disk       = Get-Disk -Number $cPartition.DiskNumber

    # Find a partition that is:
    #  - on the same disk as C:
    #  - positioned after C: (i.e. sitting between C: and the end of the disk)
    #  - small enough to plausibly be a recovery partition (<=1GB)
    #  - NOT the EFI System Partition or Microsoft Reserved Partition
    #  - has no drive letter assigned (extra safety - recovery partitions don't)
    $blockingPartitions = Get-Partition -DiskNumber $disk.Number | Where-Object {
        $_.PartitionNumber -ne $cPartition.PartitionNumber -and
        $_.Offset -gt $cPartition.Offset -and
        $_.Size -le 1GB -and
        $_.Type -notin @('System','Reserved') -and
        [string]::IsNullOrEmpty($_.DriveLetter)
    }

    If ($blockingPartitions) {
        Foreach ($part in $blockingPartitions) {
            Write-Host "Removing blocking partition #$($part.PartitionNumber) - Type: $($part.Type), Size: $([Math]::Round($part.Size/1MB)) MB" -ForegroundColor Yellow
            $part | Remove-Partition -Confirm:$false -ErrorAction Stop
        }
    } Else {
        Write-Host "No blocking partition found after C: - nothing to remove" -ForegroundColor Green
    }

    # Rescan and extend C: to max supported size
    Get-Disk | Update-Disk
    $size = Get-PartitionSupportedSize -DriveLetter C

    If ($size.SizeMax -gt $cPartition.Size) {
        Resize-Partition -DriveLetter C -Size $size.SizeMax -ErrorAction Stop
        Write-Host "Extended C: to $([Math]::Round($size.SizeMax/1GB)) GB" -ForegroundColor Green
    } Else {
        Write-Host "C: is already at maximum size" -ForegroundColor Green
    }

    Exit 0
}
Catch {
    Write-Host "Remediation error: $($_.Exception.Message)" -ForegroundColor Red
    Exit 1
}
