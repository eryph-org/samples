[CmdletBinding()]
param (

    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'cinc-server',
    [Parameter(Mandatory=$false)]
    [string]$CincPassword = 'password',
    
    [switch] $Force
)

$ErrorActionPreference = "Stop"

push-location $PSScriptRoot
Set-EryphConfigurationStore -All CurrentDirectory

if(-not (Test-Path .ssh\sshkey)){
    mkdir .ssh -ErrorAction SilentlyContinue | Out-Null
    ssh-keygen -b 2048 -t rsa -f .ssh\sshkey -q -N '""'

    # check if this version of ssh-keygen requires a different syntax
    ssh-keygen -y -P '""' -f .\.ssh\sshkey | Out-Null
    if($LASTEXITCODE -ne 0){
        Remove-Item .\.ssh\sshkey
        ssh-keygen -b 2048 -t rsa -f .ssh\sshkey -q -N ''
    }

}

$sshKey = Get-Content .ssh\sshkey.pub
$ip = ""

function invoke-ssh(
    [Parameter(Mandatory=$true)]
    [string]$command

){
    push-location $PSScriptRoot
    $sshKeyPath = Resolve-Path .ssh\sshkey
    ssh -q admin@$ip -o "IdentitiesOnly=yes" -o "StrictHostKeyChecking=no" -i $sshKeyPath -C $command
    Pop-location
}


if($true -eq $Force){
    Write-Information "removing existing catlet, if it exists" -InformationAction Continue
    Get-Catlet | where Name -eq $catletName | Remove-Catlet -Force
}else
{
    $catlet = Get-Catlet | where Name -eq $catletName
    if($catlet){
        Write-Error "catlet $catletName already exists. Use Parameter -Force to recreate it."
        return
    }
}

Write-Information "booting catlet" -InformationAction Continue
$catletConfig = Get-Content ./cinc-server.yaml
$catletConfig = $catletConfig.replace("{{sshkey}}", $sshKey)

$catletConfig | New-Catlet -Name $catletName -ErrorAction Stop | Start-Catlet -Force -ErrorAction Stop

Write-Information "waiting 30 seconds" -InformationAction Continue
Start-Sleep -Seconds 30

$catlet = Get-Catlet | Where-Object Name -eq $catletName
$catletId = $catlet.Id
$ipInfo = Get-CatletIp -Id $catletId 
$ip = $ipInfo.IpAddress

do {
    Write-Information "Waiting for bootstrapping to finish..." -InformationAction Continue
    Start-Sleep -Seconds 5
    # dir command? due to this issue: https://github.com/PowerShell/Win32-OpenSSH/issues/1334
    $finished = invoke-ssh '[ -f /installed ] && echo "found" || echo "wait"; dir; exit 0;'
    if(!$finished){
        $finished = ""
    }
    
} until ($finished.startsWith("found"))

Write-Information "Downloading and installing cinc-server. Please note that cinc downloads are quite slow, so it will take some time." -InformationAction Continue
invoke-ssh 'curl -L https://omnitruck.cinc.sh/install.sh | sudo bash -s -- -P cinc-server -v 14'

Write-Information "Configuring cinc-server..." -InformationAction Continue
start-Sleep -Seconds 1
invoke-ssh 'sudo cinc-server-ctl reconfigure'

Write-Information "Waiting 10 seconds and then generating user and org" -InformationAction Continue
Start-Sleep -Seconds 10
$userKey = invoke-ssh "sudo cinc-server-ctl user-create cinc-user cinc user none@eryph.io ${CincPassword}"
$orgKey =  invoke-ssh 'sudo cinc-server-ctl org-create dev Development -a cinc-user'

Write-Information "Saving cinc org and user keys" -InformationAction Continue
$userKey |Set-Content ./.cinc/cinc-user.pem
$orgKey | Set-Content ./.cinc/org-validator.pem

$configTemplate = gc .cinc/config.rb.template
$configTemplate = $configTemplate.replace("{{cinc_ip}}", $ip)
$configTemplate | set-Content .cinc/config.rb

Write-Information "cinc server has been setup." -InformationAction Continue
Write-Information "The following command shoud now work: knife user list" -InformationAction Continue
