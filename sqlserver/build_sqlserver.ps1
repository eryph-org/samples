#Requires -Version 5.1
#Requires -Module Eryph.ComputeClient
[CmdletBinding()]
param (

    [Parameter(Mandatory=$false)]
    [string]$CatletName = 'sqlserver',

    [Parameter(Mandatory=$true)]
    [string]$SQLServerISO,

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.Credential()]
    [System.Management.Automation.PSCredential] $Credentials 
)

$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($SQLServerISO)) {
    $SQLServerISO = (Join-Path $PSScriptRoot $SQLServerISO)
}

if(-not (Test-Path $SQLServerISO)){
    Write-Error "SQL Server ISO file not found"
    return
}

if (-not $Credentials) {
    $Credentials = Get-Credential -Message "Please provide username and password for your new catlet. The password must meet Windows Server password rules (at least 8 characters and must contain upper case, lower case and digits)."
}

Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force

Write-Information "Booting catlet..." -InformationAction Continue
$catletConfig = Get-Content -Raw -Path (Join-Path $PSScriptRoot "sqlserver.yaml")
$catletConfig = $catletConfig.Replace("{{ sqlserver_iso }}", $SQLServerISO)

$catlet = New-Catlet `
    -Name $catletName `
    -Config $catletConfig `
    -Variables @{
        username = $Credentials.GetNetworkCredential().UserName
        password = $Credentials.GetNetworkCredential().Password
    } `
    -SkipVariablesPrompt

Start-Catlet -Id $catlet.Id -Force

Write-Information "Waiting 3 minutes..." -InformationAction Continue
Start-Sleep -Seconds 180

$ipInfo = Get-CatletIp -Id $catlet.Id
$ip = $ipInfo.IpAddress

do {
    Write-Information "Waiting for connection..." -InformationAction Continue
    Start-Sleep -Seconds 10
    $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet
} until ($ping)

$opt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
$session = new-PSSession -ComputerName $ip -Credential $Credentials -UseSSL -Authentication Basic -SessionOption $opt
Invoke-Command -Session $session -scriptblock {

    $finished = Test-Path c:\SQLInstallStatus.txt

    if ($finished) { return }

    do {
        Write-Information "Waiting for SQLServer installation to finish..." -InformationAction Continue
        Start-Sleep -Seconds 10
        $finished = Test-Path c:\SQLInstallStatus.txt
    } until ($finished)
    
}

$status = Invoke-Command -Session $session -scriptblock {
    return Get-Content c:\SQLInstallStatus.txt
}

if ($status -eq "failed") {
    Write-Error "SQL Server installation failed"

    $logContent = Invoke-Command -Session $session -scriptblock {
        return Get-Content c:\SQLInstall.log
    }
    
    Write-Host $logContent

    exit
}

Write-Information "Catlet $catletname is ready for testing" -InformationAction Continue

# run Tests

Remove-PSSession -Session $session
