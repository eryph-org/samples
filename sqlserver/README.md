# Overview

This example shows how to create a catlet that automatically installs SQL Server on first boot.


## Getting Started

1. Clone this repository if you have not already done so.
2. Download a SQL Server installation ISO, e.g. from my.visualstudio.com
3. Run the `build-sqlserver.ps1' script and set the arguments to the catlet name and ISO path.

## How it works

The fodder configuration of the catlet contains a powershell script that installs SQL Server using Desired State Configuration (DSC).
See also the SQLServerDSC: https://github.com/dsccommunity/SqlServerDsc

If the installation requires a reboot, the script will return 1003 to request that it be run again at the next boot.
The result of the installation is written to log files that can be retrieved later. 

Finally, the firewall will enable ping replies so that the build-sqlserver script can ping the host. Once this happens, it will connect via Powershell Remoting and check the files written for installation status.