function Get-CloudbaseInitUserDataError {
    <#
    .SYNOPSIS
    Retrieves user data stderr error messages from Cloudbase-Init log content.

    .DESCRIPTION
    This function scans the provided Cloudbase-Init log content for lines containing errors related to user data execution, specifically `stderr` messages. It extracts and outputs only the message inside the raw byte strings for better readability.

    .PARAMETER LogContent
    The content of the Cloudbase-Init log as a string array.

    .EXAMPLE
    gc .\cloudbase-init.log | Get-CloudbaseInitUserDataError
    Scans the provided log content for user data errors and outputs the cleaned-up matching lines.
    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string]$LogContent
    )

    begin {
        $lines = @()
    }
    process {
        if ($null -ne $LogContent -and $LogContent -ne "") {
            # If LogContent is a single string with line breaks, split it into lines
            if ($LogContent -is [string] -and $LogContent -match "(\r\n|\n)") {
                $lines += $LogContent -split "`r?`n"
            } else {
                $lines += $LogContent
            }
        }
    }
    end {
        if (-not $lines -or $lines.Count -eq 0) {
            Write-Warning "LogContent is empty."
            return
        }

        $logStartPattern = '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \d+ (DEBUG|INFO|ERROR|WARNING) [\w\.\-]+ \[\-\]'
        $currentLogLine = ""
        $logLines = @()

        foreach ($line in $lines) {
            if ($line -match $logStartPattern) {
                if ($currentLogLine) {
                    $logLines += $currentLogLine
                }
                $currentLogLine = $line
            } else {
                $currentLogLine += "`n$line"
            }
        }
        if ($currentLogLine) {
            $logLines += $currentLogLine
        }

        $first = $true
        foreach ($logLine in $logLines) {
            if ($logLine -match "User_data (stdout|stderr)") {
                if ($logLine -match "b(['`"])(.*?)(\1)") {
                    $msg = $matches[2] -replace "\\r\\n|\\n", "`n"

                    if ($first) {
                        $first = $false
                        Write-Information "fodder command error(s) found in Cloudbase-Init log:" `
                         -InformationAction Continue
                    }
                    Write-Output $msg
                }
            }
        }

        if ($first) {
            Write-Warning "No fodder command error(s) found in Cloudbase-Init log. See full log"
            $logLines | Write-Output
        }
    }
}

Export-ModuleMember -Function Get-CloudbaseInitUserDataError
