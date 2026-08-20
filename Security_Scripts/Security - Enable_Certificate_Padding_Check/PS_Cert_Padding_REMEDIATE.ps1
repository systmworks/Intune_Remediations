<########################################################
    Name:       PS_Cert_Padding_REMEDIATE.ps1
    Purpose:    Enable certificate padding check registry values
    Location:   Intune
    Owner:      Darren Milne
    Comments:   

    CHANGELOG:  (dd/mm/yyyy)
        11/11/2024 - v1.0 - New Script developed
        
########################################################>

New-Item 'HKLM:\Software\Microsoft\Cryptography\Wintrust\Config' -Force
New-Item 'HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config' -Force

Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Cryptography\Wintrust\Config'             -Name 'EnableCertPaddingCheck' -Value '1' -Type 'String'
Set-ItemProperty -Path 'HKLM:\Software\Wow6432Node\Microsoft\Cryptography\Wintrust\Config' -Name 'EnableCertPaddingCheck' -Value '1' -Type 'String'
