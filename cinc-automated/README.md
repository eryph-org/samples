# Overview

This sample contains a boilerplate to setup a chef or cinc (a free build of chef) development environment automatically with eryph.
It contains a automatically created cinc-server (same as chef-server) and template to create linux or windows catlets that are
registered in the chef server. 


## Getting started

1. Clone this repository, if you have not already done so.
2. Execute script `setup.ps1` in a **elevated** command prompt. 

The setup script will install cinc workstation on your local machine. Main command of cinc workstation is the `knife` command. 
When workstation is installed a restart of the powershell (not the computer) may be required. Afterwards - when executed again the setup script will automatically install a cinc server.

You can now use the script Build-Node.ps1 to create ubuntu or windows nodes that are registered automatically in the cinc server. 

Example: 

``` ps
.\Build-Node.ps1 -CatletName node1 -Os Linux
```

## Cinc project

The example setup contains an eryph project called cinc. A dedicated client is created automatically so that you can access the project without administrative privileges. 
The project includes a network setup to separate the cinc server and clients on its own network with a single IP 10.0.0.130 so that it always gets the same IP. 
However, the nodes will use the eryph managed dns name of the cinc server (https://cinc-server.cinc.internal). 

## Nodes

The created nodes will be build from the linux-node.yaml or windows-node.yaml catlet spec file. Both contains fodder to configure the cinc client and for registration in the cinc server.
The created nodes cannot be accessed via SSH or winrm via the knife command from the host as the hostnames are only known internally in the catlet network. 
To find the current IP for remote access to catlets, use the Get-CatletIp command.

# Cinc and Chef Repository data
Every Chef Infra installation needs a Chef Repository. This is the place where cookbooks, policyfiles, config files and other artifacts for managing systems with Chef Infra will live. 
More information on the structure of a chef (and cinc) repository can be found here: https://docs.chef.io/chef_repo/
The sample repository just contains the default example cookbook.

## Repository Directories

This repository contains several directories, and each directory contains a README file that describes what it is for in greater detail, and how to use it for managing your systems with Chef.

- `cookbooks/` - Cookbooks you download or create.
- `data_bags/` - Store data bags and items in .json in the repository.
- `roles/` - Store roles in .rb or .json in the repository.
- `environments/` - Store environments in .rb or .json in the repository.

## Configuration

The config file, `.cinc/config.rb` is a repository-specific configuration file for the knife command line tool. It is automatically generated when
you execute the `Build-CincServer` script.

## Next Steps

Read the README file in each of the subdirectories for more information about what goes in those directories.
