<#
  .Synopsis
  Checks if eryph zero exists.

  .Description
  This function checks if the `eryph-zero` command is available in the current environment.

#>
function Test-EryphZeroExists {
    $zeroCommand = Get-Command eryph-zero -ErrorAction SilentlyContinue

    if (-not $zeroCommand) {
        Write-Error "Install eryph-zero to run this example."
        exit 1
    } else{
        Write-Information "command 'eryp-zero' found. Assuming eryph-zero is installed." -InformationAction Continue
    }
}

Export-ModuleMember -Function Test-EryphZeroExists

