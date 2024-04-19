# Overview

This sample contains a boilerplate to setup a chef or cinc (a free build of chef) development environment automatically with eryph.
It contains a automatically created cinc-server (same as chef-server) and template to create linux or windows catlets that are
registered in the chef server. 


## Getting started

1. Clone this repository, if you have not already done so.
2. Execute script `setup.ps1` in a **elevated** command prompt. 

The setup script will install cinc workstation on your local machine. Main command of cinc workstation is the `knife` command. 

Every Chef Infra installation needs a Chef Repository. This is the place where cookbooks, policyfiles, config files and other artifacts for managing systems with Chef Infra will live. We strongly recommend storing this repository in a version control system such as Git and treating it like source code.

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
