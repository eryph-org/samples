#Requires -Version 5.1
#Requires -Modules Eryph.ComputeClient
[CmdletBinding()]
param (

    [Parameter(Mandatory=$false)]
    [System.Management.Automation.Credential()]
    [System.Management.Automation.PSCredential] $Credentials 
)

$ErrorActionPreference = 'Stop'
$catletName = "dc1"

Import-Module -Name "$PSScriptRoot/../modules/Eryph.InvokeCommand.psm1"

if (-not $Credentials) {
    $Credentials = Get-Credential -Message "Please provide username and password for domain admin user. The password must meet Windows Server password rules (at least 8 characters and must contain upper case, lower case and digits)."
}

Write-Information "Removing existing catlet (if it exists)..." -InformationAction Continue
Get-Catlet | Where-Object Name -eq $catletName | Remove-Catlet -Force

Write-Information "Booting dc1 catlet..." -InformationAction Continue

$password = $Credentials.GetNetworkCredential().Password
$domainAdmin = $Credentials.GetNetworkCredential().UserName

$catlet = Get-Content dc1.yaml | New-Catlet `
    -Name $catletName `
    -ProjectName "winlab" `
    -SkipVariablesPrompt `
    -Variables @{
        domain_admin = $domainAdmin
        domain_admin_password = $password
        safe_mode_password = $password
    } `

Start-Catlet -Id $catlet.Id -Force

Write-Information "Waiting 2 minutes for bootstrapping..." -InformationAction Continue
Start-Sleep -Seconds 120

$ipInfo = Get-CatletIp -Id $catlet.Id
$ip = $ipInfo.IpAddress

# there are multiple ways to check if the catlet is ready
# in this case we write a installation status file
# so we can check for it using winrm

$status = Invoke-CommandWinRM -ComputerName $ip -Credential $Credentials -Retry -scriptblock {

    $finished = Test-Path c:\DCInstallStatus.txt

    if ($finished) { return }

    do {
        Write-Information "Waiting for Domain Controller installation to finish..." -InformationAction Continue
        Start-Sleep -Seconds 10
        $finished = Test-Path c:\DCInstallStatus.txt
    } until ($finished)
    
    $status = Get-Content c:\DCInstallStatus.txt

    if ($status -eq "failed") {
        Write-Error "Domain controller installation failed"

        $logContent = Invoke-Command -Session $session -scriptblock {
            return Get-Content c:\DCInstall.log
        }
        
        Write-Host $logContent

        exit
    }

    return $status
}

if ($status -eq "failed") {
    Write-Error "Domain Controller setup failed." -InformationAction Continue
    $logContent = Invoke-CommandWinRM -ComputerName $ip -Credentials $Credentials -scriptblock {
        return Get-Content "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log"
    }
    $logContent | Get-CloudbaseInitUserDataError

    return
}

# some orchestration steps to ensure the domain controller is ready

Write-Information "Waiting for Domain Controller to be ready..." -InformationAction Continue

Invoke-CommandWinRM -ComputerName $ip -Credential $Credentials -Retry -scriptblock {
    
    do {
        $netlogon = Get-Service -Name Netlogon
        $ready = $netlogon.Status -eq 'Running'
            

        if( -not $ready ) {
            Write-Information "Netlogon service is not running yet, waiting..." -InformationAction Continue
            Start-Sleep -Seconds 10
        }

    } until ($ready)
}

Write-Information "Waiting for group policies..." -InformationAction Continue

Invoke-CommandWinRM -ComputerName $ip -Credential $Credentials -Retry -scriptblock {

    while ($true) {
        # Check for Group Policy completion events in the System log
        $gpEvent = Get-WinEvent -LogName "System" -MaxEvents 50 |
            Where-Object {
                $_.ProviderName -eq "Microsoft-Windows-GroupPolicy" -and
                ($_.Id -eq 1502 -or $_.Id -eq 1503 -or $_.Id -eq 1501)
            } |
            Select-Object -First 1

        if ($gpEvent) {
            # Optionally, output event details (can be removed for silent operation)
            $gpEvent | Select-Object TimeCreated, Id, Message
            break
        }
        Start-Sleep -Seconds 5
    }
}

Write-Information "Domain Controller is ready." -InformationAction Continue
