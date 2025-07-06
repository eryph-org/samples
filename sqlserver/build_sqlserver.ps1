#Requires -Version 5.1
#Requires -Modules Eryph.ComputeClient
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
Import-Module -Name "$PSScriptRoot/../modules/Eryph.InvokeCommand.psm1"
Import-Module -Name "$PSScriptRoot/../modules/CloudInit.Analyzers.psm1"

function Get-AdminCredentials {
    Write-Host
    Write-Host "Please provide username and password for admin user. The password must meet Windows Server password rules (at least 8 characters and must contain upper case, lower case and digits)." -ForegroundColor Yellow
    $username = Read-Host "Username for admin"
    
    do {
        $password = Read-Host "admin password (hidden)" -AsSecureString
        $confirmPassword = Read-Host "Please confirm the password (hidden)" -AsSecureString

        if (([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))) -ne ([Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($confirmPassword)))) {
            Write-Host "Passwords do not match. Please try again." -ForegroundColor Red
            continue
        }

        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
        if ($plainPassword.Length -lt 8 -or `
            -not ($plainPassword -match '[A-Z]') -or `
            -not ($plainPassword -match '[a-z]') -or `
            -not ($plainPassword -match '\d')) {
            Write-Host "Password does not meet Windows Server password rules. Please try again." -ForegroundColor Red
            continue
        }

        break
    } while ($true)

    $adminCred = New-Object System.Management.Automation.PSCredential($username, $password)
    return $adminCred
}

if (-not [System.IO.Path]::IsPathRooted($SQLServerISO)) {
    $SQLServerISO = (Join-Path $PSScriptRoot $SQLServerISO)
}

if(-not (Test-Path $SQLServerISO)){
    Write-Error "SQL Server ISO file not found"
    return
}

if (-not $Credentials) {
    $Credentials = Get-AdminCredentials
}

Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force

Write-Information "Booting catlet..." -InformationAction Continue

# the catlet yaml contains a placeholder for the SQL Server ISO path
# which will be replaced with the actual path to the ISO file
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

Write-Information "Waiting 3 minutes for bootstrapping..." -InformationAction Continue
Start-Sleep -Seconds 180

$ipInfo = Get-CatletIp -Id $catlet.Id
$ip = $ipInfo.IpAddress

# when catlet is booted the fodder will create a file c:\SQLInstallStatus.txt
# with the content "finished" when the SQL Server installation is done
# or "failed" if the installation failed
# the fodder will also create a log file c:\SQLInstall.log with the installation log
Write-Information "Waiting for SQLServer installation to finish..." -InformationAction Continue
Invoke-CommandWinRM -ComputerName $ip -Credentials $Credentials -Retry -scriptblock {

    $finished = Test-Path c:\SQLInstallStatus.txt
    if ($finished) { return }
    do {
        Start-Sleep -Seconds 10
        $finished = Test-Path c:\SQLInstallStatus.txt
    } until ($finished)
    
}

# the fodder will also create a log file c:\SQLInstall.log with the installation log
$status = Invoke-CommandWinRM -ComputerName $ip -Credentials $Credentials -Retry -TimeoutInSeconds 60 -scriptblock {
    return Get-Content c:\SQLInstallStatus.txt
}

if ($status -eq "failed") {
    Write-Error "SQL Server installation failed"

    # for error handling we both read the SQLInstall.log and the cloudbase-init log
    Write-Information "Reading SQL Server installation log..." -InformationAction Continue
    $logContent = Invoke-CommandWinRM -ComputerName $ip -Credentials $Credentials -Retry -TimeoutInSeconds 60 -scriptblock {
        return Get-Content c:\SQLInstall.log
    }
    
    Write-Output $logContent

    Write-Information "Reading cloudbase-init log..." -InformationAction Continue
    $logContent = Invoke-CommandWinRM -ComputerName $ip -Credentials $Credentials -Retry -TimeoutInSeconds 60 -scriptblock {
        return Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log"
    }
    $logContent | Get-CloudbaseInitUserDataError

    exit
}

Write-Information "Catlet $catletname is ready..." -InformationAction Continue

