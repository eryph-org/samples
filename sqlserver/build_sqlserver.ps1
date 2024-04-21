[CmdletBinding()]
param (

    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'sqlserver',

    [Parameter(Mandatory=$true)]
    [string]$SQLServerISO
)

$ErrorActionPreference = 'Stop'

if(-not (Test-Path $SQLServerISO)){
    Write-Error "SQL Server ISO file not found"
    return
}

$pwUnsecure = "InitialPassw0rd"
$pw = ConvertTo-SecureString $pwUnsecure -AsPlainText -Force
$Cred = New-Object System.Management.Automation.PSCredential ("Admin", $pw)

push-location $PSScriptRoot

Write-Host "removing existing catlet, if it exists"
Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force

Write-Host "booting catlet"
$catletConfig = Get-Content ./sqlserver.yaml
$catletConfig = $catletConfig.replace("{{password}}", $pwUnsecure)
$catletConfig = $catletConfig.replace("{{sqlserver_iso}}", $SQLServerISO)

$catletConfig | New-Catlet -Name $catletName | Start-Catlet -Force

Write-Host "waiting 3 minutes"
Start-Sleep -Seconds 180

arp -d *

$catlet = Get-Catlet | Where-Object Name -eq $catletName
$catletId = $catlet.Id
$ipInfo = Get-CatletIp -Id $catletId
$ip = $ipInfo.IpAddress

do {
    Write-Host "Waiting for connection..."
    Start-Sleep -Seconds 10
    $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet
} until ($ping)

$opt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
$session = new-PSSession -ComputerName $ip -Credential $cred -UseSSL -Authentication Basic -SessionOption $opt
Invoke-Command -Session $session -scriptblock {

    $finished = Test-Path c:\SQLInstallStatus.txt

    if($finished){ return }

    do {
        Write-Host "Waiting for SQLServer installation to finish..."
        Start-Sleep -Seconds 10
        $finished = Test-Path c:\SQLInstallStatus.txt
    } until ($finished)
    
}

$status = Invoke-Command -Session $session -scriptblock {
    return Get-Content c:\SQLInstallStatus.txt
}

if($status -eq "failed"){
    Write-Host "SQL Server installation failed"

    $logContent = Invoke-Command -Session $session -scriptblock {
        return Get-Content c:\SQLInstall.log
    }
    
    Write-Host $logContent

    exit
}

Write-Host "catlet $catletname is ready for testing"

# run Tests

Remove-PSSession -Session $session