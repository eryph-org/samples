# Overview

This example shows how to create an Ubuntu catlet that automatically installs
Powershell on first boot and enables remote access via Powershell and SSH.
Additionally, variables are used parameterize the catlet configuration.

## Getting Started

1. Clone this repository if you have not already done so.
3. Run the `Build-UbuntuPwsh.ps1' script.

## How it works

The script generates an SSH keypair and then creates a new catlet with the
help of the parameterized catlet configuration.

After the catlet has been started, the script will connect with Powershell
remoting over SSH and fetch the content of `hello-world.txt`.
