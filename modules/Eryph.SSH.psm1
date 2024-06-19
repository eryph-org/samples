<#
  .Synopsis
  Creates a new SSH key and returns the public key data.

  .Description
  Creates a new SSH key without a passphrase. The key will only be
  created when the key file does not already exist.

  .Parameter KeyFilePath
  The path where the key file should be stored.

  .Parameter Force
  Overwrites an existing key file.
#>
function New-SSHKey {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $KeyFilePath,
        [switch] $Force
    )

    # Use legacy argument parsing. This way, we can pass the empty passphrase
    # to ssh-keygen in the same way independent of the Powershell version.
    $PSNativeCommandArgumentPassing = 'Legacy'

    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        throw "Could not find ssh-keygen. Please install the SSH client."
    }

    $keyExists = Test-Path $KeyFilePath

    if ($keyExists -and $Force) {
        Remove-Item "$KeyFilePath*"
    }

    $keyDirectoryPath = [System.IO.Path]::GetDirectoryName($KeyFilePath)
    if (-not (Test-Path $keyDirectoryPath)) {
        New-Item -ItemType Directory -Path $keyDirectoryPath
    }

    if ((-not $keyExists) -or $Force) {
        $null = ssh-keygen -b 2048 -t rsa -f $KeyFilePath -q -N '""'
        if (-not $?) {
            throw "Could not generate the SSH key."
        }
    }
    
    $publicKey = ssh-keygen -y -f $KeyFilePath -P '""'
    if (-not $?) {
        throw "Could not read the SSH public key."
    }
    return $publicKey
}

<#
  .Synopsis
  Invokes a command on a remote machine via SSH.

  .Description
  Connects to a remote machine using SSH and executes the
  given command. SSH will skip the host key check.

  .Parameter Command
  The command to execute on the remote machine.

  .Parameter Hostname
  The host to which SSH should connect.

  .Parameter Username
  The username with which SSH should connect.

  .Parameter KeyFilePath
  The private key with which SSH should authenticate.
#>
function Invoke-SSH {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $Command,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $Hostname,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $Username,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $KeyFilePath
    )

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        throw "Could not find ssh. Please install the SSH client."
    }

    if (-not (Test-Path $KeyFilePath)) {
        throw "The SSH key file does not exist."
    }

    # Use legacy argument parsing. This way, the command invocation will behave
    # the same in old and new versions of Powershell.
    $PSNativeCommandArgumentPassing = 'Legacy'
    
    $result = ssh -q "$Username@$Hostname" `
        -o 'IdentitiesOnly=yes' `
        -o 'StrictHostKeyChecking=no' `
        -i $KeyFilePath `
        -C $Command
    
    return $result
}

<#
  .Synopsis
  Installs the SSH client.

  .Description
  Installs the SSH client Windows feature.
#>
function Install-SSHClient {

    $sshCommand = Get-Command ssh -ErrorAction SilentlyContinue

    if (-not $sshCommand) {
        Write-Information "SSH Client not found. Going to install the Windows feature..." -InformationAction Continue
        Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*' | Add-WindowsCapability -Online
    }
}

Export-ModuleMember -Function New-SSHKey
Export-ModuleMember -Function Invoke-SSH
Export-ModuleMember -Function Install-SSHClient
