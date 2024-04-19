[CmdletBinding()]
param (

    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'node',

    [Parameter(Mandatory=$false)]
    [ValidateSet('Linux','Windows')]    
    [string]$Os = 'Linux',

    [Parameter(Mandatory=$false)]    
    [string]$Parent,

    [Parameter(Mandatory=$false)]    
    [string]$Environment = "development",
     
    [switch] $Force
)

push-location $PSScriptRoot
Set-EryphConfigurationStore -All CurrentDirectory

if(-not (Test-Path .ssh\sshkey)){
    mkdir .keys -ErrorAction SilentlyContinue | Out-Null
    ssh-keygen -b 2048 -t rsa -f .ssh\sshkey -q -N ''
}

if(-not (Test-Path .cinc\org-validator.pem)){
    Write-Error "Cinc organization key not found. Please run script build_cincserver.ps1 first."
    return
}

$validatorKey = Get-Content .cinc\org-validator.pem

$sshKey = Get-Content .ssh\sshkey.pub

if($true -eq $Force){
    Write-Information "removing existing catlet, if it exists" -InformationAction Continue
    $catlet = Get-Catlet | Where-Object Name -eq $catletName
    
    if($catlet){
        $id = $catlet.Id
        & knife node delete $id -y 
        $catlet | Remove-Catlet -Force 
    }

}else
{
    $catlet = Get-Catlet | Where-Object Name -eq $catletName
    if($catlet){
        Write-Error "catlet $catletName already exists. Use Parameter -Force to recreate it."
        return
    }
}

Write-Information "creating catlet" -InformationAction Continue

if($os -eq "Linux"){
$catletConfig = Get-Content ./linux-node.yaml } 
else{
$catletConfig = Get-Content ./windows-node.yaml
}

$catletConfig = $catletConfig.replace("{{sshkey}}", $sshKey)

# shift lines of validator key so it matches yaml syntax of generated catlet
$validatorKey | ForEach-Object {
    if($_ -match "-----BEGIN RSA PRIVATE KEY-----"){
        $validatorKeyShifted += "$_`n"
    }else{
        $validatorKeyShifted += "        $_`n"
    }
}

$validatorKeyShifted = $validatorKeyShifted.TrimStart()
$catletConfig = $catletConfig.replace("{{validation_key}}", $validatorKeyShifted)
$catletConfig = $catletConfig.replace("{{environment}}", $environment)

if($parent) {
    $catlet = $catletConfig | New-Catlet -Name $catletName -Parent $parent | Start-Catlet -Force -ErrorAction Stop
} else{
    $catlet = $catletConfig | New-Catlet -Name $catletName | Start-Catlet -Force -ErrorAction Stop
}
arp -d *

if($os -eq 'Linux'){
    Write-Information "Wait 30 seconds for node bootstrapping..." -InformationAction Continue
    start-sleep -Seconds 30
} else{
    Write-Information "Windows nodes need some time for booting and cinc installation." -InformationAction Continue
    Write-Information "Get some coffee and take a break..." -InformationAction Continue
    Write-Information "Wait 5 minutes for node bootstrapping..." -InformationAction Continue
    start-sleep -Seconds 300
}
do {
    Write-Information "Wait until node is registered..." -InformationAction Continue
    
    $catletId = $catlet.Id
    $nodeInfo = knife node show $catletId 2>&1

    if($os -eq 'Linux'){
     Start-Sleep -Seconds 10
} else{
     Start-Sleep -Seconds 30
}
    
    
} until ($nodeInfo -match 'FQDN')


Write-Information "Catlet $($catlet.Name) is ready." -InformationAction Continue
$nodeInfo