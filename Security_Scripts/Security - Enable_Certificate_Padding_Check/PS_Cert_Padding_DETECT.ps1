<########################################################
    Name:       PS_Cert_Padding_DETECT.ps1
    Purpose:    Detect EnableCertPaddingCheck registry values
    Location:   Intune
    Owner:      Darren Milne
    Comments:   This script only checks the regkeys - it does NOT make any changes.

    CHANGELOG:  (dd/mm/yyyy)
        11/11/2024 - v1.0 - New Script developed
        
########################################################>

$keys = @(
    [pscustomobject]@{
        keyPath='HKLM:\Software\Microsoft\Cryptography\Wintrust\Config'
        keyName='EnableCertPaddingCheck'
        keyValue='1'
    }
    [pscustomobject]@{
        keyPath='HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
        keyName='EnableCertPaddingCheck'
        keyValue='1'
    }
)

Function Test-ValueExists {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Path
    ,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Value
    )

    try {
        Get-ItemPropertyValue -Path $Path -Name $Value -ErrorAction Stop | Out-Null
        Return $true
    }
    catch {
        Return $false
    }
}


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

$totalKeys = $keys.Count
$keyCount = 0

try {
    foreach ($key in $keys) {

        If (Test-ValueExists -Path $key.KeyPath -Value $key.keyName) {
            $Value = Get-ItemPropertyValue -Path $key.keyPath -Name $key.keyName
            
            If ($Value -eq $key.keyValue) {
                $isSet=$true
            } Else {
                $isSet=$false
            }
            
        } Else {
            $isSet=$false
        }

        If (!$isSet) {
            Write-Output "Missing: $($key.keyPath) - $($key.keyName)"
            $keyCount++    # increment the counter
        }

    }
    If ($keyCount -eq 0) {
        Write-Host "All $totalKeys keys present and correct :)"
        Exit 0
    } Else {
        Write-Host "$keyCount of $totalKeys keys missing or incorrect :("
        Exit 1
    }

} catch {
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
}
