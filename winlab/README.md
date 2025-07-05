# Overview

This sample contains a boilerplate to setup a windows lab environment with eryph.
It contains a a script to setup a project for the lab and to configure first domain controller and management VM.

To run the example you need some free memory (between 6 and 12 GB, more is always better).

## Getting started

1. Clone this repository, if you have not already done so.
2. Execute script `setup.ps1` in a **elevated** command prompt. 

The setup script will setup a eryph configuration and a project for the lab. Then it will bootstrap the domain controller and management VM.
A dedicated client is created automatically so that you can access the project without administrative privileges after running the setup.

You can also add additional member with the `Build-Member` powershell script. It accepts either a Windows Server Version (2019,2022,2025) or a parent name to build a member of your choice. The script is only necessary for orchestration / checking state of member, so you can also just deploy your own catlet into the domain using the `member.yaml` catlet as template. 


## How it works

Setting up a Windows domain within eryph is a two-stage process: 
1. First Domain controller(s) have to be created and bootstrapped. 
2. Then DNS Server settings have to be configured for the domain network. Therefore we recommend running the domain in its own project. Within the project you can reconfigure the networks default DNS Servers to the domain controller. 