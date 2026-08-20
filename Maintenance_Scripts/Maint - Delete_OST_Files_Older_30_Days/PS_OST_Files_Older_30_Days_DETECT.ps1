<########################################################
    Name:       PS_OST_Files_Older_30_Days_DETECT.ps1
    Purpose:    Detect stale OST files (not modified in over 30 days)
    Location:   Intune
    Owner:      Darren Milne
    Comments:   

    CHANGELOG:  (dd/mm/yyyy)
        11/11/2024 - v1.0 - New Script developed
        
########################################################>

# Find OST files in every Users Outlook folder
$allOst = Get-ChildItem -Path "C:\Users\*\AppData\Local\Microsoft\Outlook\*.ost"

# Filter to those not modified in over 30 days
$staleOst = $allOst | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }

# Count and Sum the files
$staleOstCount = $staleOst.Count
$staleOstSumGB = [math]::Round( ( ($staleOst | Measure -Property length -Sum).Sum /1GB),1)

If ($staleOstCount -gt 0) {
    Write-Host "Found $staleOstCount stale OST file(s) consuming $staleOstSumGB GB" -ForegroundColor Red
    Exit 1
} Else {
    Write-Host "No stale OST files found" -ForegroundColor Green
    Exit 0
}
