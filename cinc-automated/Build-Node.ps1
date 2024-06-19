#Requires -Version 5.1
#Requires -Modules Eryph.ComputeClient
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

Import-Module -Name "$PSScriptRoot/../modules/Eryph.SSH.psm1"

$sshPublicKey = New-SSHKey -KeyFilePath "$PSScriptRoot/.ssh/sshkey"

if (-not (Test-Path .cinc\org-validator.pem)) {
    Write-Error "Cinc organization key not found. Please run script build_cincserver.ps1 first."
    return
}

$cincCalidationKey = Get-Content -Raw .cinc\org-validator.pem
# We escape the line breaks as the validation key is inserted
# into the YAML cloud-init configuration. Inside the YAML,
# the string is in double quotes which makes sure that the
# escaped line breaks are interpreted correctly.
$cincValidationKey = $cincCalidationKey.Replace("`r`n", "`n").Replace("`n", "\n").Trim();

if ($true -eq $Force) {
    Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
    $catlet = Get-Catlet | Where-Object Name -eq $catletName
    
    if ($catlet) {
        $id = $catlet.Id
        & knife node delete $id -y 
        $catlet | Remove-Catlet -Force 
    }

} else {
    $catlet = Get-Catlet | Where-Object Name -eq $catletName
    if ($catlet) {
        Write-Error "Catlet $catletName already exists. Use Parameter -Force to recreate it."
        return
    }
}

Write-Information "Creating catlet..." -InformationAction Continue

if ($os -eq "Linux") {
    $catletConfig = Get-Content -Raw ./linux-node.yaml } 
else {
    $catletConfig = Get-Content -Raw ./windows-node.yaml
}

$variables = @{
    cincValidationKey = $cincValidationKey
    sshPublicKey = $sshPublicKey
}

if ($parent) {
    $catlet = New-Catlet -Name $catletName -Config $catletConfig -Parent $parent -Variables $variables -SkipVariablesPrompt -ErrorAction Stop
} else {
    $catlet = New-Catlet -Name $catletName -Config $catletConfig -Variables $variables -SkipVariablesPrompt -ErrorAction Stop
}

Start-Catlet -Id $catlet.Id -Force -ErrorAction Stop

if ($os -eq 'Linux') {
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

    if ($os -eq 'Linux') {
        Start-Sleep -Seconds 10
    } else{
        Start-Sleep -Seconds 30
    }
} until ($nodeInfo -match 'FQDN')

Write-Information "Catlet $($catlet.Name) is ready." -InformationAction Continue
$nodeInfo
