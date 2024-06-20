#Requires -Version 5.1
#Requires -Modules Eryph.ComputeClient
[CmdletBinding()]
param (

    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'cinc-server',
    [Parameter(Mandatory=$false)]
    [string]$CincPassword = 'password',
    
    [switch] $Force
)

$ErrorActionPreference = "Stop"

Import-Module -Name "$PSScriptRoot/../modules/Eryph.SSH.psm1"

push-location $PSScriptRoot
Set-EryphConfigurationStore -All CurrentDirectory

$cincServerUsername = 'admin'
$sshKeyPath = "$PSScriptRoot/.ssh/sshkey"
$sshPublicKey = New-SSHKey -KeyFilePath $sshKeyPath

if ($true -eq $Force) {
    Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
    Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force
} else {
    $catlet = Get-Catlet | Where-Object Name -eq $catletName
    if ($catlet) {
        Write-Error "Catlet $catletName already exists. Use Parameter -Force to recreate it."
        return
    }
}

Write-Information "Booting catlet..." -InformationAction Continue
$catletConfig = Get-Content -Raw ./cinc-server.yaml

$catlet = New-Catlet -Name $catletName `
    -Config $catletConfig `
    -Variables @{
        username = $cincServerUsername  
        sshPublicKey = $sshPublicKey
    } `
    -SkipVariablesPrompt `
    -ErrorAction Stop 

Start-Catlet -Id $catlet.Id -Force -ErrorAction Stop

Write-Information "Waiting 30 seconds..." -InformationAction Continue
Start-Sleep -Seconds 30

$catletIpInfo = Get-CatletIp -Id $catlet.Id 
$ip = $catletIpInfo.IpAddress

do {
    Write-Information "Waiting for bootstrapping to finish..." -InformationAction Continue
    Start-Sleep -Seconds 5
    # dir command? due to this issue: https://github.com/PowerShell/Win32-OpenSSH/issues/1334
    $finished = Invoke-SSH `
        -Command '[ -f /installed ] && echo "found" || echo "wait"; dir; exit 0;' `
        -Hostname $ip `
        -Username  $cincServerUsername `
        -KeyFilePath $sshKeyPath

    if (!$finished) {
        $finished = ""
    }
    
} until ($finished.startsWith("found"))

Write-Information "Downloading and installing cinc-server. Please note that cinc downloads are quite slow, so it will take some time." -InformationAction Continue
Invoke-SSH `
    -Command 'curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-server -v 14' `
    -Hostname $ip `
    -Username  $cincServerUsername `
    -KeyFilePath $sshKeyPath

Write-Information "Configuring cinc-server..." -InformationAction Continue
Start-Sleep -Seconds 1
Invoke-SSH `
    -Command 'sudo cinc-server-ctl reconfigure' `
    -Hostname $ip `
    -Username  $cincServerUsername `
    -KeyFilePath $sshKeyPath

Write-Information "Waiting 10 seconds and then generating user and org" -InformationAction Continue
Start-Sleep -Seconds 10
$userKey = Invoke-SSH `
    -Command "sudo cinc-server-ctl user-create cinc-user cinc user none@eryph.io ${CincPassword}" `
    -Hostname $ip `
    -Username  $cincServerUsername `
    -KeyFilePath $sshKeyPath
$orgKey =  Invoke-SSH `
    -Command 'sudo cinc-server-ctl org-create dev Development -a cinc-user' `
    -Hostname $ip `
    -Username  $cincServerUsername `
    -KeyFilePath $sshKeyPath

Write-Information "Saving cinc org and user keys" -InformationAction Continue
$userKey | Set-Content ./.cinc/cinc-user.pem
$orgKey | Set-Content ./.cinc/org-validator.pem

$configTemplate = Get-Content -Raw .cinc/config.rb.template
$configTemplate = $configTemplate.replace("{{cinc_ip}}", $ip)
$configTemplate | set-Content .cinc/config.rb

Write-Information "cinc server has been setup." -InformationAction Continue
Write-Information "The following command shoud now work: knife user list" -InformationAction Continue
