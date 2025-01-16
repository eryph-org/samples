# Overview

This folder contains some tutorials to learn the basics of catlet configuration.

## Getting Started

1. Clone this repository.
2. Install eryph!  See https://github.com/eryph-org/eryph/blob/main/src/apps/src/Eryph-zero/README.md  
(If you're still on the waitlist, you can't do this, sorry!)
3. Open the tutorial folder in a **elevated** PowerShell prompt (as Administrator).

## Tutorial 0: Basics

You can create a new catlet quickly from a parent with the `New-Catlet` command:

`New-Catlet -Parent <Org>/<Geneset>/<Tag>`

Catlets are stored in **genesets** on the eryph **genepool** (something like the Docker Hub). The `<Org>/<Geneset>/<Tag>` syntax is the address of a geneset. 

- Org: Name of organization on genepool, e.g. dbosoft
- Geneset: Name of geneset
- a geneset tag, optional (default is **latest**)

Example:

``` pwsh
New-Catlet -Parent dbosoft/ubuntu-22.04/starter
```

or 

``` pwsh
New-Catlet -Parent dbosoft/ubuntu-22.04
```
for latest geneset.   
The eryph genepool contains artifacts that can be shared within eryph - these artifacts are called genes. Genes of same purpose can be grouped in a geneset.

The catlet parent genes will be downloaded from the eryph genepool if it isn't already available locally. It may take up to GB (for example for a Windows parent). If you have a limited amount of data on your Internet connection, do not do it without thinking about it ;-)

You can see your catlet now in Hyper-V Manager and can start it like any other VM, or you can use the start-Catlet cmdlet to run it:


``` pwsh
Get-Catlet  | Start-Catlet -Force
```

When the catlet is started, it automatically configures itself by eating all food you provided. In case of the starter catlet the configuration already contains fodder that creates a user **admin** with password **admin**. 

### Other useful cmdlets

- **Get-Catlet**:  
  Shows a list or a single catlet if you add the catlet id. Catlets are always identifed by an id. The name of a catlet is only unique within a project (we will come later to projects).
- **Remove-Catlet**:  
  To remove a catlet by its id

To remove all catlets simple use a powershell pipeline:

``` pswh
Get-Catlet | Remove-Catlet -Force
```

### Catlets must be unique within a project
Note that we did not specify a name for the catlet. In this case, the default name "catlet" will be used. If you create another catlet without a name, you will get a name conflict error.  
Within a project, all catlets must have a unique name. Since we did not specify the project either, the default project "default" is used.
To avoid this error, either specify a name for newly created catlets or remove the previously created catlet: 

``` pwsh

# use name for new catlets
New-Catlet -Name newcatlet -Parent dbosoft/ubuntu-22.04

# or remove the other catlet by name:
Get-Catlet | where Name -eq "catlet" | Remove-Catlet -Force
```

## Tutorial 1: Catlet specs

Instead of writing always everything on the command line you should write more complex catlet specs in files.  

A simple example:

``` yaml
# file: catlet.yaml
name: catlet2
parent: dbosoft/ubuntu-22.04/starter
```

Such a spec file can then be passed to New-Catlet via powershell pipeline: 

``` pwsh
# if you saved it as catlet.yaml
gc ./catlet.yaml | New-Catlet  
```

The file `tutorial-1.yaml` shows you how to set simple settings like name, parent and memory size. Run following command to create and start the catlet:

``` pwsh
gc ./tutorial-1.yaml | New-Catlet | Start-Catlet -Force
```

Now we would like to ssh into the catlet. Do do so, you will need ssh installed on your host. This repo contains a helper module for ssh so let`s use it: 

``` pwsh
Import-Module -Name "../modules/Eryph.SSH.psm1"
Install-SSHClient
```

Next, we will look up the catlet IP.   
A catlet gets an internal IP that's accessible within its project. If no project is specified, it uses the default. So catlet internal Ip will be something like 10.0.0.11.
To access a catlet from the host, each catlet also has a NAT IP.  

You can lookup both information with the `Get-CatletIp` cmdlet: 

``` pwsh
Get-CatletIp -Internal # for internal IP
Get-CatletIp # for host NAT ip

# now you can ssh into your machine: 
ssh admin@<HOST NAT IP> #password: admin

```

All catlets within the same project can reach each other but no other catlet from another project. 


## Tutorial 2: Fodder

It's time to feed our catlets!  

With fodder you specify how a catlet configures itself. 

Have a look at `tutorial-2.yaml`.   
You can see a section fodder containing some config to set up a apache server.  
If you already have automatically set up machines in the cloud this may look familiar to you. Exactly - fooder content will be injected as [cloud-init](https://cloud-init.io/) configuration into your catlet!

So let`s create a apache server: 

``` pwsh

# cleanup previous catlets:
Get-Catlet | Remove-Catlet -Force

# create new catlet
gc ./tutorial-2.yaml | New-Catlet | Start-Catlet -Force
Get-CatletIp
```

Give your catlets some seconds to boot, then you can access the apache default page from your browser: `http://<Catlet Host NAT IP>`

A catlet may contain multiple fodder configurations. All of them will be merged together in the order you specify to fodder. 

``` yaml

fodder: 
 - name: food1
     [...]
 - name: food2
     [...]    
```

Like catlets fodder can also be shared on the genepool. Thats exactly what the catlet on the starter tag does.  

See how the geneset `dbosoft/ubuntu-22.04/starter` is declared: 

 ``` yaml
parent: dbosoft/ubuntu-22.04/latest
fodder:
 - source: gene:dbosoft/starter-food:linux-starter
```


>**For experts**:  
> Actually dbosoft/ubuntu-22.04/starter is a ref to dbosoft/ubuntu-22.04/starter-[version], but let`s skip that detail for now.

You can build and publish your own fodder on the eryph genepool to share it between your organization or even make it public and available for everyone!



## Tutorial 3: Fodder Variables

Catlet and fodder specs offer a clear advantage in terms of standardization. This allows you to repeat your configuration again and again until it works, then reuse it for other catlets.  

However, there are situations where you may need some variability in the final configuration, especially when it comes to secure information like passwords and keys. This is where variables come in.  
With variables, you can declare variables within catlets and fodder genes that have to be provided when the catlet is created.

So far we have used always the default password `admin` for the user. 
In `tutorial-3.yaml` we now declare a variable for the password, so you have to provide it when creating the catlet:

 ``` 
gc ./tutorial-3.yaml | New-Catlet | Start-Catlet -Force
```

You will then see a prompt like this:
```
Catlet variables
Would you like to provide variable values interactively? Some required variables are missing values. The deployment
will fail if you do not specify them.
[Y] Yes  [N] No  [R] Required only  [?] Help (default is "R"):
[String] password:
```

Variables can be used only in fodder but can be declared both in catlets and fodder genes.  
If a fodder gene is used with required variables a catlet has either to provide a value for then or to declare its own input variables to provide them.


## Tutorial 4: Projects and Networks

Each catlet is assigned and unique within a project. If you do not specify otherwise, all catlets are automatically assigned to the default project.  
A project provides isolation between catlets. This means that each catlet can only "see" catlets in the same project. Projects could also have different members, so you can also separate who has access to a project.

Here are some examples of how this can be used:
- Build a testing infrastructure locally from a Git repository.
- You have set up a central test machine in your local IT office and would like to provide isolated test environments to each team member.
- You would like to run different software versions on the same  - simulated - infrastructure using same  hostnames and ip addresses as in production.
- You would like to isolate machines on a DMZ host. 


To create a project you execute the `New-EryphProject` cmdlet:

``` pwsh
New-EryphProject tutorial
```

A project can declare its own network layout without considering the networks of other projects.
You can download the default set up network of a project with the Get-VNetwork cmdlet and upload a new network configuration with Set-VNetwork:


``` pwsh
Get-VNetwork -ProjectName tutorial -config

# to import the project network we have prepared for you:
gc ./tutorial-network.yaml | Set-VNetwork -ProjectName tutorial

```

You can now add a catlet to a project by settings with `project: <project name>`, like in tutorial-4.yaml:

``` pwsh

# create new catlet
gc ./tutorial-4.yaml | New-Catlet | Start-Catlet -Force
Get-CatletIp -Internal
```

If you have imported tutorial-network.yaml into your project you will now see that the internal ip of the catlet has changed and will be something in a 172.16.0.0/20 network.

### Provider Networks
You might be wondering how you can access catlets from another host even if it's not covered in detail in this tutorial.  

This is where provider network configuration comes in. You have the option of configuring eryph to use your existing network for communication with the catlets from the host or other machines instead of using the default NAT overlay network mode.  
You can even disable overlay networking completely and use the default Hyper-V networking mode if you don't need isolation or network configuration.

You can find more information about this in the docs - [Advanced Networking](https://www.eryph.io/docs/advanced-networking).

> **Remarks:**  
> Cross project networking is currently not supported, but will be added in future. However you can allow communication between projects always on provider network. 
