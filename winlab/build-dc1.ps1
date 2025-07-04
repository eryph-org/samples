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

Write-Information "Waiting 3 minutes..." -InformationAction Continue
Start-Sleep -Seconds 180

$ipInfo = Get-CatletIp -Id $catlet.Id
$ip = $ipInfo.IpAddress
$opt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
 
do{

    do {
        Write-Information "Waiting for network connection..." -InformationAction Continue
        Start-Sleep -Seconds 10
        $ping = Test-Connection -ComputerName $ip -Count 1 -Quiet
    } until ($ping)

    try{
        Write-Information "Waiting for WinRM connection..." -InformationAction Continue
        Start-Sleep -Seconds 10
        $session = new-PSSession -ComputerName $ip -Credential $Credentials -UseSSL -Authentication Basic -SessionOption $opt
        if($session) {
            $winrm = $true
        } else {
            $winrm = $false
        }

        Invoke-Command -Session $session -scriptblock {

            $finished = Test-Path c:\DCInstallStatus.txt

            if ($finished) { return }

            do {
                Write-Information "Waiting for Domain Controller installation to finish..." -InformationAction Continue
                Start-Sleep -Seconds 10
                $finished = Test-Path c:\DCInstallStatus.txt
            } until ($finished)
            
        }

        $status = Invoke-Command -Session $session -scriptblock {
            return Get-Content c:\DCInstallStatus.txt
        }

        if ($status -eq "failed") {
            Write-Error "Domain controller installation failed"

            $logContent = Invoke-Command -Session $session -scriptblock {
                return Get-Content c:\DCInstall.log
            }
            
            Write-Host $logContent

            exit
        }

        Write-Information "Waiting for Domain Controller to be ready..." -InformationAction Continue
        do {
            
            $ready = Invoke-Command -Session $session -scriptblock {
                # Check if Netlogon is running
                $netlogon = Get-Service -Name Netlogon
                $netlogon.Status -eq 'Running'
            }

            if( -not $ready ) {
                Write-Information "Netlogon service is not running yet, waiting..." -InformationAction Continue
                Start-Sleep -Seconds 10
            }

        } until ($ready)

        Write-Information "Waiting for group policies..." -InformationAction Continue
        Invoke-Command -Session $session -scriptblock {
            $timeoutSeconds = 600  # Set a timeout (e.g., 10 minutes)
            $startTime = Get-Date

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

                # Check for timeout
                if ((Get-Date) - $startTime -gt (New-TimeSpan -Seconds $timeoutSeconds)) {
                    Write-Error "Timed out waiting for Group Policy to finish."
                    break
                }
                Start-Sleep -Seconds 5
            }
        }

        Write-Information "Domain Controller is ready." -InformationAction Continue

    }
    catch {
        Write-Warning "WinRM Error $_" -ErrorAction Continue
        Write-Information "WinRM connection failed, retrying..." -InformationAction Continue
        $winrm = $false
    }

} until ($winrm)


Remove-PSSession -Session $session
