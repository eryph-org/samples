#Requires -Version 5.1
#Requires -Modules Eryph.IdentityClient, Eryph.ComputeClient
#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Import-Module -Name "$PSScriptRoot/../modules/Eryph.SSH.psm1"
Import-Module -Name "$PSScriptRoot/../modules/Eryph.LocalProject.psm1"
Import-Module -Name "$PSScriptRoot/../modules/Eryph.Check.psm1"

Push-Location $PSScriptRoot

# setup and checks
#--------------------

Write-Information "Checking if SSH is installed..." -InformationAction Continue
Install-SSHClient

Write-Information "Checking if eryph-zero exists..." -InformationAction Continue
Test-EryphZeroExists

Write-Information "Checking project and credentials" -InformationAction Continue
Set-EryphConfigurationStore -All CurrentDirectory
Initialize-EryphProjectAndClient cinc -ClientAsDefault

# project network configuration
#------------------------------

Get-Content network.yaml | Set-VNetwork -ProjectName cinc

Pop-Location

# ensure chef/ cinc-workstation is installed
#-------------------------------------------

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

# create cinc-server catlet
#--------------------------

$serverCatlet = Get-Catlet | Where-Object Name -eq cinc-server
if (-not $serverCatlet) {
    Write-Information "Creating catlet for cinc-server" -InformationAction Continue
    .\Build-CincServer.ps1
}
