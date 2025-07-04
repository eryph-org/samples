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


Push-Location $PSScriptRoot

Write-Information "Checking if eryph-zero exists..." -InformationAction Continue

$zeroCommand = Get-Command eryph-zero -ErrorAction SilentlyContinue

if (-not $zeroCommand) {
    Write-Error "Install eryph-zero to run this example."
    exit 1
} else{
    Write-Information "command 'eryp-zero' found. Assuming eryph-zero is installed." -InformationAction Continue
}


Write-Information "Checking credentials for eryph..." -InformationAction Continue

$sysCred = Get-EryphClientCredentials -SystemClient -Configuration zero

if (-not $sysCred) {
    return
}

Set-EryphConfigurationStore -All CurrentDirectory
$configuration = Get-EryphClientConfiguration -Configuration zero -ErrorAction SilentlyContinue | Where-Object Name -eq 'winlab'

if (-not $configuration) {
    Write-Information "Creating a new eryph client for this project" -InformationAction Continue

    Remove-Item .eryph -Recurse -ErrorAction SilentlyContinue
    new-eryphclient -name winlab -AllowedScopes compute:write -AddToConfiguration -AsDefault -Credentials $sysCred
} else {
    Write-Information "Client for eryph exists" -InformationAction Continue
}

$clientId = (Get-EryphClientConfiguration -Configuration zero -ErrorAction SilentlyContinue | Where-Object Name -eq 'winlab').Id

Write-Information "Checking if eryph project 'winlab' exists..." -InformationAction Continue
$project = Get-EryphProject -Credentials $sysCred | Where-Object Name -eq 'winlab'

if (-not $project) {
    Write-Information "Creating a new eryph project" -InformationAction Continue
    $project = New-EryphProject winlab -Credentials $sysCred
} else {
    Write-Information "project 'winlab' found" -InformationAction Continue
}


$role = Get-EryphProjectMemberRole -ProjectName "winlab"  -Credentials $sysCred `
    | Where-Object { $_.Project.Id -eq ($project.Id) }`
    | Where-Object MemberId -eq $clientId

if (-not $role) {
    Write-Information "Adding client to project" -InformationAction Continue
    Add-EryphProjectMemberRole -ProjectName winlab -MemberId $clientId -Role owner -Credentials $sysCred
} else {
    Write-Information "Client is already a member of project" -InformationAction Continue
}

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