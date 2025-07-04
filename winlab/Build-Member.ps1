#Requires -Version 5.1
#Requires -Modules Eryph.ComputeClient
[CmdletBinding()]
param (

    [Parameter(Mandatory=$true, ParameterSetName="ServerVersion")]
    [Parameter(Mandatory=$true, ParameterSetName="Parent")]
    [Parameter(Mandatory=$true, ParameterSetName="AdminHost")]   
    [string]$CatletName,

    [Parameter(Mandatory=$false, ParameterSetName="ServerVersion")]
    [ValidateSet('2019','2022', '2025')]    
    [string]$ServerVersion = '2022',

    [Parameter(Mandatory=$false, ParameterSetName="AdminHost")]    
    [switch]$admin,

    [Parameter(Mandatory=$true,ParameterSetName="Parent")]    
    [string]$Parent,

    [Parameter(Mandatory=$false, ParameterSetName="ServerVersion")]
    [Parameter(Mandatory=$false, ParameterSetName="Parent")]
    [Parameter(Mandatory=$false, ParameterSetName="AdminHost")]    
    [System.Management.Automation.Credential()]
    [System.Management.Automation.PSCredential] $Credentials 
)

$ErrorActionPreference = 'Stop'

function Get-AdminCredentials {
    Write-Host
    Write-Host "Please provide username and password for domain admin user." -ForegroundColor Yellow
    Write-Host "Same credentials will also be used for local admin user." -ForegroundColor Yellow
    $username = Read-Host "Username for domain admin"
    
    do {
        $password = Read-Host "Domain admin password (hidden)" -AsSecureString
        $confirmPassword = Read-Host "Please confirm the password (hidden)" -AsSecureString

        if (([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))) -ne ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)))) {
            Write-Host "Passwords do not match. Please try again." -ForegroundColor Red
            continue
        }
        break
    } while ($true)

    $adminCred = New-Object System.Management.Automation.PSCredential($username, $password)
    return $adminCred
}


push-location $PSScriptRoot
Set-EryphConfigurationStore -All CurrentDirectory

if(-not $Credentials) {
    $Credentials = Get-AdminCredentials
}

if(-not $Parent){
    $parent = "dbosoft/winsrv$ServerVersion-standard"
}

$variables = @{
    domain_admin = $Credentials.GetNetworkCredential().UserName
    domain_admin_password = $Credentials.GetNetworkCredential().Password
}

if ($admin) {
    $catletSpec = Get-Content admin.yaml
} else {
    $catletSpec = Get-Content member.yaml
    $catletSpec = $catletSpec -replace '{{parent}}', $Parent
}


$catlet = $catletSpec | New-Catlet `
    -Name $catletName `
    -ProjectName "winlab" `
    -SkipVariablesPrompt `
    -Variables $variables


Start-Catlet -Id $catlet.Id -Force -ErrorAction Stop

Write-Information "Wait 30 seconds for bootstrapping..." -InformationAction Continue
start-sleep -Seconds 30

$ipInfo = Get-CatletIp -Id $catlet.Id
$ip = $ipInfo.IpAddress
$opt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck

Write-Information "Connecting..." -InformationAction Continue

do{

    do {
        $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet

        if (-not $ping) {
            Write-Information "Waiting for network connection..." -InformationAction Continue
            Start-Sleep -Seconds 10
        }
    } until ($ping)

    try{
        $session = new-PSSession -ComputerName $ip -Credential $Credentials -UseSSL -Authentication Basic -SessionOption $opt
        if($session) {
            $winrm = $true
        } else {
            Write-Information "Waiting for WinRM connection..." -InformationAction Continue
            Start-Sleep -Seconds 10    
            $winrm = $false
        }

        Invoke-Command -Session $session -scriptblock {

            do {
                
                $initService = Get-Service -Name cloudbase-init
                $finished = $initService.Status -eq 'Stopped'

                if (-not $finished) {
                    Write-Information "Waiting for cloud-init..." -InformationAction Continue
                    Start-Sleep -Seconds 10
                }
            } until ($finished)
            
        }

        $ready = Invoke-Command -Session $session -scriptblock {
            # check if member has joined the domain
            $domainJoined = (Get-WmiObject Win32_ComputerSystem).Domain
            if ($domainJoined -eq 'WORKGROUP') {
                return $false
            } else {
                return $true
            }
        }

        if ($ready) {
            Write-Information "Catlet has joined the domain." -InformationAction Continue
        } else {
            Write-Information "Catlet has not joined the domain. Check log:" -InformationAction Continue
            Invoke-Command -Session $session -scriptblock {
                Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log"
            }
        }
    }
    catch {
        Write-Warning "WinRM Error $_" -ErrorAction Continue
        Write-Information "WinRM connection failed, retrying..." -InformationAction Continue
        $winrm = $false
    }

} until ($winrm)


Remove-PSSession -Session $session
