#Requires -Version 5.1
#Requires -Modules Eryph.IdentityClient, Eryph.ComputeClient
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

function Get-AdminCredentials {
    Write-Host
    Write-Host "Please provide username and password for domain admin user. The password must meet Windows Server password rules (at least 8 characters and must contain upper case, lower case and digits)." -ForegroundColor Yellow
    $username = Read-Host "Username for domain admin"
    
    do {
        $password = Read-Host "Domain admin password (hidden)" -AsSecureString
        $confirmPassword = Read-Host "Please confirm the password (hidden)" -AsSecureString

        if (([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))) -ne ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)))) {
            Write-Host "Passwords do not match. Please try again." -ForegroundColor Red
            continue
        }

        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
        if ($plainPassword.Length -lt 8 -or `
            -not ($plainPassword -match '[A-Z]') -or `
            -not ($plainPassword -match '[a-z]') -or `
            -not ($plainPassword -match '\d')) {
            Write-Host "Password does not meet Windows Server password rules. Please try again." -ForegroundColor Red
            continue
        }

        break
    } while ($true)

    $adminCred = New-Object System.Management.Automation.PSCredential($username, $password)
    return $adminCred
}

Import-Module -Name "$PSScriptRoot/../modules/Eryph.LocalProject.psm1"
Import-Module -Name "$PSScriptRoot/../modules/Eryph.Check.psm1"


Push-Location $PSScriptRoot

Write-Information "Checking if eryph-zero exists..." -InformationAction Continue
Test-EryphZeroExists


Set-EryphConfigurationStore -All CurrentDirectory

Write-Information "Checking project and credentials" -InformationAction Continue
Initialize-EryphProjectAndClient winlab -ClientAsDefault

# reset project dns of dc1 is not found
# this may happen if the dc was deleted and setup is run again

$dc1Catlet = Get-Catlet | Where-Object Name -eq dc1

if (-not $dc1Catlet) {
 Write-Information "Initializing project network configuration..." -InformationAction Continue
 $networkConfig = Get-Content -Raw -Path network.yaml
 $dnsServers = @("8.8.8.8", "9.9.9.9")
 $dnsServersYaml = ($dnsServers | ForEach-Object { "     - $_" }) -join "`n"
 $networkConfig = $networkConfig -replace "{{ dns_servers }}", $dnsServersYaml

 Set-VNetwork -ProjectName winlab -Config $networkConfig

}

if (-not $dc1Catlet) {
    Write-Information "Creating catlet for first domain controller" -InformationAction Continue

    if($null -eq $Credentials) {
         $Credentials = Get-AdminCredentials
    }

    .\Build-dc1.ps1 -Credentials $Credentials
}

Set-Location $PSScriptRoot

$dcatlets = Get-Catlet | Where-Object Name -like "dc*"
if(-not $dcatlets) {
    Write-Error "Domain controller catlets not found."
    exit 1
}

$dnsServers = @()

$dcatlets | ForEach-Object {
    $ipInfo = Get-CatletIp -Id $_.Id -InternalIp
    $ip = $ipInfo.IpAddress
    $dnsServers += $ip
    Write-Information "Found domain controller $($_.Name) with IP $ip" -InformationAction Continue
}


$networkConfig = Get-Content -Raw -Path network.yaml
$dnsServersYaml = ($dnsServers | ForEach-Object { "     - $_" }) -join "`n"
$networkConfig = $networkConfig -replace "{{ dns_servers }}", $dnsServersYaml

Write-Information "Updating project network configuration with DNS servers: $($dnsServers -join ', ')" -InformationAction Continue
Set-VNetwork -ProjectName winlab -Config $networkConfig

Write-Information "Building admin host..." -InformationAction Continue
.\Build-Member.ps1 -CatletName "admhost" -Credentials $Credentials -admin

Write-Information "Domain is ready for use" -InformationAction Continue
Write-Information "To create a additional member run script Build-Member.ps1" -InformationAction Continue
Write-Information "Login IP Information for all catlets:" -InformationAction Continue
Get-CatletIp