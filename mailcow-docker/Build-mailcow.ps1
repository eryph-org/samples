#Requires -Version 5.1
#Requires -Modules Eryph.ComputeClient
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'mailcow'
)

$ErrorActionPreference = 'Stop'

Import-Module -Name "$PSScriptRoot/../modules/Eryph.SSH.psm1"

$sshKeyDirectory = Join-Path $PSScriptRoot ".ssh"
$sshKeyName = "sshkey"
$sshKeyPath = Join-Path $sshKeyDirectory $sshKeyName

Install-SSHClient
$sshPublicKey = New-SSHKey -KeyFilePath $sshKeyPath

Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
Get-Catlet | Where-Object Name -eq $catletName | Stop-Catlet -Force -Mode Hard -ErrorAction SilentlyContinue
Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force

$catletConfigPath = Join-Path $PSScriptRoot "mailcow.yaml"

Write-Information "Creating new catlet..." -InformationAction Continue
$catlet = New-Catlet `
    -Name $CatletName `
    -Config (Get-Content -Raw -Path $catletConfigPath) `
    -Variables @{
        sshPublicKey = $sshPublicKey
        username = "admin"
    } `
    -SkipVariablesPrompt

Start-Catlet -Id $catlet.Id -Force

Write-Information "Waiting for 10 seconds..." -InformationAction Continue
Start-Sleep -Seconds 10

$catletIpInfo = Get-CatletIp -Id $catlet.Id
$ip = $catletIpInfo.IpAddress

Write-Information "Connecting to the new catlet..." -InformationAction Continue

Invoke-SSH `
-Command "ls /" `
-Hostname $ip `
-Username  "admin" `
-KeyFilePath $sshKeyPath `
-ErrorAction Continue | Out-Null

Write-Information "Waiting for cloud-init to finish..." -InformationAction Continue
# get cloud-init status, this will block until cloud-init is finished
Invoke-SSH `
-Command "sudo cloud-init status --wait" `
-Hostname $ip `
-Username  "admin" `
-KeyFilePath $sshKeyPath `
-ErrorAction Continue


# check if mailcow is installed
$ready = Invoke-SSH `
-Command "sudo docker compose ls | grep mailcowdockerized" `
-Hostname $ip `
-Username  "admin" `
-KeyFilePath $sshKeyPath `
-ErrorAction SilentlyContinue `

if ($ready) {
    Write-Information "Mailcow is installed and running." -InformationAction Continue
    Write-Information "You can access the Mailcow web interface at http://$ip" -InformationAction Continue
} else {

    Write-Error "Mailcow is not installed or not running." -ErrorAction Continue
    Write-Information "Reading logs..." -InformationAction Continue

    $logContent = Invoke-SSH `
    -Command "cd /opt/mailcow-dockerized; sudo docker compose logs" `
    -Hostname $ip `
    -Username  "admin" `
    -KeyFilePath $sshKeyPath `
    -ErrorAction SilentlyContinue

    if(-not $logContent){
        # collect cloud-init logs if docker logs are not available
        $logContent = Invoke-SSH `
        -Command "sudo cat /var/log/cloud-init-output.log" `
        -Hostname $ip `
        -Username  "admin" `
        -KeyFilePath $sshKeyPath `
        -ErrorAction SilentlyContinue
    }

    if(-not $logContent){
        $logContent = "No logs available."
    }

    Write-Output $logContent
}


Write-Information "You can connect to the catlet via SSH using the following command:" -InformationAction Continue
Write-Information "ssh -i $sshKeyPath admin@$ip" -InformationAction Continue
