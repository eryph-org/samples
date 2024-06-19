#Requires -Version 6
#Requires -Modules Eryph.ComputeClient
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'ubuntu-pwsh',

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.Credential()]
    [System.Management.Automation.PSCredential] $Credentials 
)

$ErrorActionPreference = 'Stop'

Import-Module -Name "$PSScriptRoot/../modules/Eryph.SSH.psm1"

if (-not $Credentials) {
    $Credentials = Get-Credential -Message "Please provide username and password for your new catlet."
}

$sshKeyDirectory = Join-Path $PSScriptRoot ".ssh"
$sshKeyName = "sshkey"
$sshKeyPath = Join-Path $sshKeyDirectory $sshKeyName

Install-SSHClient
$sshPublicKey = New-SSHKey -KeyFilePath $sshKeyPath

Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force

$catletConfigPath = Join-Path $PSScriptRoot "ubuntu-pwsh.yaml"

Write-Information "Creating new catlet..." -InformationAction Continue
$catlet = New-Catlet `
    -Name $CatletName `
    -Config (Get-Content -Raw -Path $catletConfigPath) `
    -Variables @{
        sshPublicKey = $sshPublicKey
        username = $Credentials.GetNetworkCredential().UserName
        password = $credentials.GetNetworkCredential().Password
    } `
    -SkipVariablesPrompt

Start-Catlet -Id $catlet.Id -Force

Write-Information "Waiting for 10 seconds..." -InformationAction Continue
Start-Sleep -Seconds 10

$catletIpInfo = Get-CatletIp -Id $catlet.Id

Write-Information "Connecting to the new catlet..." -InformationAction Continue
$psSession = New-PSSession `
    -HostName $catletIpInfo.IpAddress `
    -UserName $Credentials.GetNetworkCredential().UserName `
    -Options @{ StrictHostKeyChecking = "no" } `
    -KeyFilePath $sshKeyPath
Invoke-Command -Session $psSession -ScriptBlock { Get-Content -Path /hello-world.txt }
Remove-PSSession $psSession
