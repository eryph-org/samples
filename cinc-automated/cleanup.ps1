#Requires -Version 5.1
#Requires -Modules Eryph.IdentityClient, Eryph.ComputeClient
#Requires -RunAsAdministrator
<#
    .Synopsis
    Cleans up the cinc project and associated catlets.

    .Description
    This script checks if the cinc project exists and removes it along with any associated catlets and credentials.
    It also checks for the existence of the cinc-workstation and prompts the user to uninstall it manually if it exists.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param()

$ErrorActionPreference = "Stop"

Import-Module -Name "$PSScriptRoot/../modules/Eryph.LocalProject.psm1"
Import-Module -Name "$PSScriptRoot/../modules/Eryph.Check.psm1"

Push-Location $PSScriptRoot

# ShouldProcess logic
$whatIfPreference = $PSCmdlet.WhatIfPreference
$confirmPreference = $PSCmdlet.ConfirmPreference

# pre-checks
#-----------

Write-Information "Checking if eryph-zero exists..." -InformationAction Continue
Test-EryphZeroExists


Write-Verbose "Checking if cinc-workstation exists..." -InformationAction Continue

$knifeCommand = Get-Command knife -ErrorAction SilentlyContinue

if ($knifeCommand) {
    # uninstall cinc-workstation
    Write-Information "cinc-workstation is not automatically uninstalled." -InformationAction Continue
    Write-Information "Please uninstall it manually if you do not need it anymore." -InformationAction Continue
}

if ($PSCmdlet.ShouldProcess("Project 'cinc' and all associated catlets", "Remove")) {
     Write-Information "Removing project and credentials" -InformationAction Continue
    Set-EryphConfigurationStore -All CurrentDirectory
    Remove-EryphProjectAndClient cinc

    Set-Location $PSScriptRoot
    Remove-Item .eryph -Force -ErrorAction SilentlyContinue -Recurse | Out-Null
    Remove-Item .ssh -Force -ErrorAction SilentlyContinue -Recurse | Out-Null
    Remove-Item .cinc/cinc-user.pem -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item .cinc/config.rb -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item .cinc/org-validator.pem -Force -ErrorAction SilentlyContinue | Out-Null

    Pop-Location

    Write-Information "Cleanup completed successfully." -InformationAction Continue
    Write-Information "To remove also downloaded genesets run following command:" -InformationAction Continue
    Write-Information "Remove-CatletGene -Unused" -InformationAction Continue
} else {
    Write-Information "Operation cancelled by user or running with -WhatIf." -InformationAction Continue
}
