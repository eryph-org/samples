#Requires -Version 5.1
#Requires -Modules Eryph.IdentityClient, Eryph.ComputeClient
#Requires -RunAsAdministrator
<#
    .Synopsis
    Cleans up the cinc project and associated catlets.

    .Description
    This script checks if the winloab project exists and removes it along with any associated catlets and credentials.
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

if ($PSCmdlet.ShouldProcess("Project 'winlab' and all associated catlets", "Remove")) {
     Write-Information "Removing project and credentials" -InformationAction Continue
    Set-EryphConfigurationStore -All CurrentDirectory
    Remove-EryphProjectAndClient winlab

    Set-Location $PSScriptRoot
    Remove-Item .eryph -Force -ErrorAction SilentlyContinue -Recurse | Out-Null

    Pop-Location

    Write-Information "Cleanup completed successfully." -InformationAction Continue
    Write-Information "To remove also downloaded genesets run following command:" -InformationAction Continue
    Write-Information "Remove-CatletGene -Unused" -InformationAction Continue
} else {
    Write-Information "Operation cancelled by user or running with -WhatIf." -InformationAction Continue
}
