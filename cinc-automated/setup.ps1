#Requires -Version 5.1
#Requires -Modules Eryph.IdentityClient
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module -Name "$PSScriptRoot/../modules/Eryph.SSH.psm1"

Push-Location $PSScriptRoot

Write-Information "Checking if SSH is installed" -InformationAction Continue
Install-SSHClient

Write-Information "Checking if eryph-zero exists..." -InformationAction Continue

$zeroCommand = Get-Command eryph-zero -ErrorAction SilentlyContinue

if (-not $zeroCommand) {
    Write-Information "Downloading and installing eryph-zero." -InformationAction Continue
    Invoke-Expression "& { $(Invoke-RestMethod https://raw.githubusercontent.com/eryph-org/eryph/main/src/apps/src/Eryph-zero/install.ps1) }"
} else{
    Write-Information "command 'eryp-zero' found. Assuming eryph-zero is installed." -InformationAction Continue
}


Write-Information "Checking credentials for eryph..." -InformationAction Continue

$sysCred = Get-EryphClientCredentials -SystemClient -Configuration zero

if (-not $sysCred) {
    return
}

Set-EryphConfigurationStore -All CurrentDirectory
$configuration = Get-EryphClientConfiguration -Configuration zero -ErrorAction SilentlyContinue | Where-Object Name -eq 'cinc'

if (-not $configuration) {
    Write-Information "Creating a new eryph client for this project" -InformationAction Continue

    Remove-Item .eryph -Recurse -ErrorAction SilentlyContinue
    new-eryphclient -name cinc -AllowedScopes compute:write -AddToConfiguration -AsDefault -Credentials $sysCred
} else {
    Write-Information "Client for eryph exists" -InformationAction Continue
}

$clientId = (Get-EryphClientConfiguration -Configuration zero -ErrorAction SilentlyContinue | Where-Object Name -eq 'cinc').Id

Write-Information "Checking if eryph project 'cinc' exists..." -InformationAction Continue
$project = Get-EryphProject -Credentials $sysCred | Where-Object Name -eq 'cinc'

if (-not $project) {
    Write-Information "Creating a new eryph project" -InformationAction Continue
    $project = New-EryphProject cinc -Credentials $sysCred
} else {
    Write-Information "project 'cinc' found" -InformationAction Continue
}

$role = Get-EryphProjectMemberRole -ProjectName cinc  -Credentials $sysCred `
    | Where-Object ProjectId -eq ($project.Id) `
    | Where-Object MemberId -eq $clientId

if (-not $role) {
    Write-Information "Adding client to project" -InformationAction Continue
    Add-EryphProjectMemberRole -ProjectName cinc -MemberId $clientId -Role owner -Credentials $sysCred
} else {
    Write-Information "Client is already a member of project" -InformationAction Continue
}


Get-Content network.yaml | Set-VNetwork

Pop-Location

Write-Information "Checking if cinc-workstation exists..." -InformationAction Continue

$knifeCommand = Get-Command knife -ErrorAction SilentlyContinue

if (-not $knifeCommand) {
    Write-Information "Downloading and installing cinc-workstation. Please note that cinc downloads are quite slow, so it will take some time." -InformationAction Continue
    . { Invoke-WebRequest -useb https://omnitruck.cinc.sh/install.ps1 } | Invoke-Expression; install -project cinc-workstation -version 22
    Write-Warning "Please restart powershell and execute setup script again to continue."
    return
} else {
    Write-Information "command 'knife' found. Assuming cinc-workstation is installed." -InformationAction Continue
}

$serverCatlet = Get-Catlet | Where-Object Name -eq cinc-server
if (-not $serverCatlet) {
    Write-Information "Creating catlet for cinc-server" -InformationAction Continue
    .\Build-CincServer.ps1
}
