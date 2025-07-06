# Overview

This example shows how to create an Ubuntu catlet that automatically installs
mailcow within docker.

## Getting Started

1. Clone this repository if you have not already done so.
3. Run the `Build-mailcow.ps1' script.

## How it works

The script generates an SSH keypair and then creates a new catlet with the
help of the parameterized catlet configuration.
The actual mailcow configuration is within the catlet fodder. The script is
only used wait for cloud-init final state and to check for errors. 

