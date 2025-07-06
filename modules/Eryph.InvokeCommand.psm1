function Invoke-CommandWinRM {
    <#
    .SYNOPSIS
    Executes a command on a remote machine using WinRM.

    .DESCRIPTION
    This function establishes a WinRM session to a remote machine, executes a script block, and returns the result.
    It supports retrying the connection and execution in case of failure, with a configurable timeout.

    .PARAMETER ComputerName
    The name or IP address of the remote machine.

    .PARAMETER Credentials
    The credentials used to authenticate with the remote machine.

    .PARAMETER scriptblock
    The script block to execute on the remote machine.

    .PARAMETER TimeoutInSeconds
    The maximum time to wait for the command execution. Default is 600 seconds.

    .PARAMETER Retry
    If specified, retries the connection and command execution in case of failure.

    .EXAMPLE
    Invoke-CommandWinRM -ComputerName "192.168.1.10" -Credentials $cred -Command { Get-Process } -Retry -TimeoutInSeconds 300
    Executes the Get-Process command on the remote machine using WinRM.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$Credentials,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutInSeconds = 600,

        [Parameter(Mandatory = $false)]
        [switch]$Retry
    )

    $ErrorActionPreference = 'Stop'

    $opt = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    $startTime = Get-Date

    do {
        Write-Verbose "Checking network connection to $ComputerName..." -InformationAction Continue

        do {
            $elapsedTime = (Get-Date) - $startTime
            $progressPercent = [math]::Round(($elapsedTime.TotalSeconds / $TimeoutInSeconds) * 100)
            $remainingSeconds = [math]::Round($TimeoutInSeconds - $elapsedTime.TotalSeconds)
            if ($remainingSeconds -lt 0) {
                $remainingSeconds = 0
            }
            Write-Progress -Activity "Waiting for network connection" `
                            -Status "$remainingSeconds seconds left before timeout..." `
                            -PercentComplete $progressPercent
                            
            $previousPreference = $Global:ProgressPreference
            $Global:ProgressPreference = 'SilentlyContinue'

            try{
                $ping = Test-NetConnection -ComputerName $ComputerName -Port 5986 `
                    -InformationLevel Quiet `
                    -WarningAction SilentlyContinue
            }
            finally{
                $Global:ProgressPreference = $previousPreference
            }

            if (-not $ping) {
                Write-Verbose "Waiting for network connection..." -InformationAction Continue
                Start-Sleep -Seconds 10
            }
        } until ($ping)

        try {
            Write-Verbose "Creating WinRM session to $ComputerName..." -InformationAction Continue
            $session = New-PSSession -ComputerName $ComputerName -Credential $Credentials -UseSSL -Authentication Basic -SessionOption $opt

            if ($session) {
                Write-Verbose "WinRM session established..." -InformationAction Continue

                Write-Progress -Activity "Waiting for network connection" `
                -Completed `
                -Status "Network connection established." `
                -PercentComplete 100

                $result = Invoke-Command -Session $session -ScriptBlock $ScriptBlock
                Remove-PSSession -Session $session
                return $result
            } else {
                Write-Warning "Failed to establish WinRM session. Retrying..." -ErrorAction Continue
            }
        } catch {
            Write-Warning "WinRM Error: $_" -ErrorAction Continue

            if($retry){
                Write-Information "Retrying connection..." -InformationAction Continue
            }
        }
        finally {
            if ($session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }

        if ($Retry) {
            Start-Sleep -Seconds 10
        }

        $elapsedTime = (Get-Date) - $startTime
    } while ($Retry -and $elapsedTime.TotalSeconds -lt $TimeoutInSeconds)

    throw "Failed to execute command via WinRM within the timeout period of $TimeoutInSeconds seconds."
}

function Invoke-CommandSSH {
    <#
    .SYNOPSIS
    Executes a command on a remote machine using SSH.

    .DESCRIPTION
    This function establishes an SSH connection to a remote machine, executes a command, and returns the result.
    It supports retrying the connection and execution in case of failure, with a configurable timeout.

    .PARAMETER ComputerName
    The name or IP address of the remote machine.

    .PARAMETER Username
    The username used to authenticate with the remote machine.

    .PARAMETER KeyFilePath
    The path to the SSH private key file.

    .PARAMETER Command
    The command to execute on the remote machine.

    .PARAMETER TimeoutInSeconds
    The maximum time to wait for the command execution. Default is 600 seconds.

    .PARAMETER Retry
    If specified, retries the connection and command execution in case of failure.

    .EXAMPLE
    Invoke-CommandSSH -ComputerName "192.168.1.10" -Username "admin" -KeyFilePath "C:\keys\private.key" -Command "ls -la" -Retry -TimeoutInSeconds 300
    Executes the "ls -la" command on the remote machine using SSH.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,

        [Parameter(Mandatory = $true)]
        [string]$Username,

        [Parameter(Mandatory = $true)]
        [string]$KeyFilePath,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutInSeconds = 600,

        [Parameter(Mandatory = $false)]
        [switch]$Retry
    )

    $ErrorActionPreference = 'Stop'
    $previousPreference = $Global:ProgressPreference
    $Global:ProgressPreference = 'SilentlyContinue'

    try{
        $startTime = Get-Date

        do {
            Write-Information "Checking network connection to $ComputerName..." 
            -InformationAction Continue

            do {
                $ping = Test-NetConnection -ComputerName $ComputerName -Port 22 `
                -InformationLevel Quiet `
                -WarningAction SilentlyContinue

                if (-not $ping) {
                    Write-Information "Waiting for network connection..." -InformationAction Continue
                    Start-Sleep -Seconds 10
                }
            } until ($ping)

            try {
                Write-Information "Executing SSH command on $ComputerName..." -InformationAction Continue
                $result = Invoke-SSH `
                    -Command $Command `
                    -Hostname $ComputerName `
                    -Username $Username `
                    -KeyFilePath $KeyFilePath

                if ($result) {
                    Write-Information "Command executed successfully via SSH." -InformationAction Continue
                    return $result
                } else {
                    Write-Warning "Failed to execute command via SSH. Retrying..." -ErrorAction Continue
                }
            } catch {
                Write-Warning "SSH Error: $_" -ErrorAction Continue
                Write-Information "Retrying connection..." -InformationAction Continue
            }

            if ($Retry) {
                Start-Sleep -Seconds 10
            }

            $elapsedTime = (Get-Date) - $startTime
        } while ($Retry -and $elapsedTime.TotalSeconds -lt $TimeoutInSeconds)

        throw "Failed to execute command via SSH within the timeout period of $TimeoutInSeconds seconds."
    }
    finally {
        $Global:ProgressPreference = $previousPreference
    }
}

Export-ModuleMember -Function Invoke-CommandSSH
Export-ModuleMember -Function Invoke-CommandWinRM