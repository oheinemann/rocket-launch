# ROCKET LAUNCH
A toolset to bootstrap a full customizable development system. This does not assume you're doing web development but installs the minimal set of software every developer will want.

## Introduction
This project was developed to bring a Mac or PC to a defined state and ready for immediate use with little effort.

Currently, it can be used to install software on a Mac with version 10.9 or higher, an Ubuntu or Debian distribution either directly or as a WSL2 variant under Windows.
As a Windows subsystem Linux, the project also provides everything necessary on the Windows host system.

## Features
- Enables the macOS application firewall (for better security)
- Enables full-disk encryption and saves the FileVault Recovery Key to the Desktop (for better security)
- Installs the Xcode Command Line Tools (for compilers and Unix tools)
- Agree to the Xcode license (for using compilers without prompts)
- Installs the latest macOS software updates (for better security)
- Installs [Homebrew](http://brew.sh) (for installing command-line software)
- Installs [Homebrew Services](https://github.com/Homebrew/homebrew-services) (for managing Homebrew-installed services)
- Installs [Homebrew Cask](https://github.com/caskroom/homebrew-cask) (for installing graphical software)
- Idempotent


# WSL2setup

This script allows you to quickly get up and running with WSL2 on Windows 10 Build 2004.
This script allows allows for easy install of various Linux distros.

## Quickstart on Winndows

To quickly get up and running with WSL2, open a new PowerShell window as "Admin" and run the following one-liner:

```posh
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/oheinemann/rocket-launch/main/wsl2-install.ps1'))
```

You will have to run this one-liner twice.
* Once to install Windows pre-requisites
* Once after the computer re-boots to update the WSL2 kernel and install a WSL distro (Ubuntu 18.04 recommended)


## Quickstart on Linux/Mac

Run the following command in your Terminal to install and bootstrap ROCKET LAUNCH:

```bash
curl -s https://raw.githubusercontent.com/oheinemann/rocket-launch/main/install.sh | bash

```
