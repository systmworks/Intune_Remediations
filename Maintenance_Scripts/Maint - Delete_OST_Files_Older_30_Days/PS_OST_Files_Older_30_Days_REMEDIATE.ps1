<########################################################
    Name:       PS_OST_Files_Older_30_Days_REMEDIATE.ps1
    Purpose:    Remove stale OST files (not modified in over 30 days)
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

# Remove the stale OST files
$staleOst | ForEach { Remove-Item $_ -Force }
