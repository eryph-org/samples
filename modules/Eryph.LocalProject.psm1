#Requires -Version 5.1
#Requires -Modules Eryph.IdentityClient, Eryph.ComputeClient
#Requires -RunAsAdministrator
<#
    .Synopsis
    Ensures that eryph client and project are created.

    .Description
    This function checks if a project and client exist in eryph, and creates them if they do not.

    .Parameter ProjectName
    Name of the project to create in eryph.

    .Parameter ClientName
    Name of the client to create in eryph. Defaults to the project name.

    .Parameter AllowedScopes
    Scopes that the client should have. Defaults to 'compute:write'.
#>
function Initialize-EryphProjectAndClient {
        param(
                [Parameter(Mandatory = $true, Position = 0)]
                [ValidateNotNullOrEmpty()]
                [string] $ProjectName,

                [Parameter(Mandatory = $false)]
                [ValidateNotNullOrEmpty()]
                [string] $ClientName = $ProjectName,

                [Parameter(Mandatory = $false)]
                [ValidateNotNullOrEmpty()]
                [string[]] $AllowedScopes = @(
                        'compute:write'
                ),

                [Parameter(Mandatory = $false)]
                [switch] $ClientAsDefault
        )

        Set-EryphConfigurationStore -All CurrentDirectory

        $sysCred = Get-EryphClientCredentials `
                -SystemClient `
                -Configuration zero

        if (-not $sysCred) {
                return
        }
        # Check if client configuration and client exist
        $configuration = Get-EryphClientConfiguration `
                -Configuration zero `
                -ErrorAction SilentlyContinue |
                Where-Object Name -eq $ClientName

        if ($configuration) {
                $identityClient = Get-EryphClient `
                        -Id $configuration.Id `
                        -Credentials $sysCred

                if ($identityClient) {
                        if ($identityClient.AllowedScopes -notcontains $AllowedScopes) {
                                Write-Information `
                                        "Updating allowed scopes for client '$ClientName'" `
                                        -InformationAction Continue
                                $identityClient | Set-EryphClient `
                                        -AllowedScopes $AllowedScopes `
                                        -Credentials $sysCred
                        }
                        else {
                                Write-Information `
                                        "Client '$ClientName' already exists." `
                                        -InformationAction Continue
                        }
                }
                else {
                        Write-Warning `
                                "Client '$ClientName' configuration found, but client not found. Removing configuration." `
                                -InformationAction Continue
                        Remove-EryphClientConfiguration `
                                -Id $configuration.Id `
                                -Configuration zero `
                                Out-Null
                        $configuration = $null
                }
        }

        if (-not $configuration) {
                Write-Information `
                        "Creating a new eryph client for project '$ProjectName'" `
                        -InformationAction Continue
                New-EryphClient `
                        -Name $ClientName `
                        -AllowedScopes $AllowedScopes `
                        -Credentials $sysCred `
                        -AddToConfiguration |`
                        Out-Null
        }

        $configuration = Get-EryphClientConfiguration `
                -Configuration zero `
                -ErrorAction SilentlyContinue |
                Where-Object Name -eq $ClientName

        $clientId = $configuration.Id 

        # check if client is set as default
        if ($ClientAsDefault) {
            if(-not $configuration.IsDefault){
                Write-Information `
                        "Setting client '$ClientName' as default client." `
                        -InformationAction Continue
                Set-EryphClientConfiguration `
                        -Id $clientId `
                        -Configuration zero `
                        -IsDefault $true `
            }
            else {
                Write-Verbose `
                        "Client '$ClientName' is already set as default." `
                        -InformationAction Continue
            }
        }        

        # Check if project exists and create it if not
        Write-Verbose `
                "Checking if project '$ProjectName' exists..." `
                -InformationAction Continue
        $project = Get-EryphProject `
                -Credentials $sysCred |
                Where-Object Name -eq $ProjectName

        if (-not $project) {
                Write-Information `
                        "Creating project '$ProjectName'" `
                        -InformationAction Continue
                $project = New-EryphProject `
                        $ProjectName `
                        -Credentials $sysCred
        }
        else {
                Write-Information `
                        "Project '$ProjectName' already exists." `
                        -InformationAction Continue
        }

        $role = Get-EryphProjectMemberRole `
                -ProjectName $ProjectName `
                -Credentials $sysCred |
                Where-Object { $_.Project.Id -eq ($project.Id) } |
                Where-Object MemberId -eq $clientId

        if (-not $role) {
                Write-Information `
                        "Adding client to project" `
                        -InformationAction Continue
                Add-EryphProjectMemberRole `
                        -ProjectName $ProjectName `
                        -MemberId $clientId `
                        -Role owner `
                        -Credentials $sysCred `
                        | Out-Null
        }
        else {
                Write-Verbose `
                        "Client '$ClientName' is already a member of project '$ProjectName'" `
                        -InformationAction Continue
        }
}

<#
    .Synopsis
    Ensures that eryph client and project are deleted.

    .Description
    This function checks if a project and client exist in eryph, and deletem them if they do.

    .Parameter ProjectName
    Name of the project to delete from eryph.

    .Parameter ClientName
    Name of the client to delete from eryph. Defaults to the project name.

#>
function Remove-EryphProjectAndClient {
        param(
                [Parameter(Mandatory = $true, Position = 0)]
                [ValidateNotNullOrEmpty()]
                [string] $ProjectName,

                [Parameter(Mandatory = $false)]
                [ValidateNotNullOrEmpty()]
                [string] $ClientName = $ProjectName
        )

        Set-EryphConfigurationStore -All CurrentDirectory


        $sysCred = Get-EryphClientCredentials `
                -SystemClient `
                -Configuration zero

        if (-not $sysCred) {
                return
        }
        # Check if client configuration and client exist
        $configuration = Get-EryphClientConfiguration `
                -Configuration zero `
                -ErrorAction SilentlyContinue |
                Where-Object Name -eq $ClientName

        if ($configuration) {
                $identityClient = Get-EryphClient `
                        -Id $configuration.Id `
                        -Credentials $sysCred `
                        -ErrorAction SilentlyContinue

                if ($identityClient) {                       
                        Write-Information `
                                "Deleting client '$ClientName'..." `
                                -InformationAction Continue
                        $identityClient | Remove-EryphClient `
                                -Credentials $sysCred | `
                                Out-Null
                }

                Write-Information `
                        "Deleting client configuration..." `
                        -InformationAction Continue
                Remove-EryphClientConfiguration `
                        -Id $configuration.Id `
                        -Confirm:$false `
                        -Force `
                        -Configuration zero | `
                        Out-Null
        }
        else {
                Write-Information `
                        "No client configuration found for '$ClientName'." `
                        -InformationAction Continue
        }

        # Check if project exists and create it if not
        Write-Verbose `
                "Checking if project '$ProjectName' exists..." `
                -InformationAction Continue
        $project = Get-EryphProject `
                -Credentials $sysCred |
                Where-Object Name -eq $ProjectName

        if (-not $project) {
                Write-Information `
                        "Project '$ProjectName' not found." `
                        -InformationAction Continue
        }
        else {
                Write-Information `
                        "Deleting Project '$ProjectName'.." `
                        -InformationAction Continue
                Remove-EryphProject `
                        -Id $project.Id `
                        -Force `
                        -Credentials $sysCred | `
                        Out-Null        
        }

}        

Export-ModuleMember -Function Initialize-EryphProjectAndClient
Export-ModuleMember -Function Remove-EryphProjectAndClient