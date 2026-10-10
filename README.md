# Hubsabai CLI

`hsb` is the command-line tool of the Hubsabai SDK: it creates and upgrades integration
workspaces, and runs the Hubsabai Designer that VS Code and AI agents (over MCP) work with.

This repository holds the installers only. The CLI and the Designer are proprietary and are
downloaded from Datasabai's package feeds: the installer fetches `hsb`, and `hsb designer start`
fetches the Designer of the same version on first use.

> **Status:** for Datasabai developers only.

## Requirements

- **JDK 25** on `PATH` or in `JAVA_HOME`
- **A token for the Hubsabai feed**: an Azure DevOps personal access token with *Packaging: Read*.
  The installer reads it from `HSB_FEED_TOKEN`, or from `~/.m2/settings.xml` (server
  `hubsabai-sdk` or `hubsabai-maven`, the one your workspaces already use), or asks for it.
  It is never written to disk.
- Windows, Linux, macOS, or Windows with WSL. Install `hsb` where your workspace files live:
  inside WSL when you work in WSL.

## Install

Linux, WSL, macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
```

Then open a new terminal, check the machine and create a workspace:

```sh
hsb doctor
hsb workspace init
hsb designer start
```

### Options

| install.sh | install.ps1 | |
|---|---|---|
| `--version 1.4.0` | `-Version 1.4.0` | a specific version (also how to roll back) |
| `--channel dev` | `-Channel dev` | every build of `dev` instead of releases (needs the Datasabai VPN) |
| `--modify-path` | `-NoModifyPath` | the shell installer only prints the PATH line unless asked; the PowerShell one adds it to your user PATH unless told not to |

Options go after `sh -s --`, or through a script block in PowerShell:

```sh
curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh -s -- --channel dev
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1))) -Channel dev
```

## What gets installed

```
~/.hubsabai/
  bin/hsb, bin/hsb.cmd          on your PATH: run the current version
  current                       the version in use
  versions/<version>/bin/       that version's launcher
  versions/<version>/lib/       hsb-cli.jar, and hsb-designer.jar once fetched
```

The current version and one previous version are kept.

## Update

```sh
hsb update            # newest version of your channel
hsb update --check    # is there one? (installs nothing)
hsb update --to 1.3.0 # a specific version, also how to roll back
```

A running Designer of another version switches the next time `hsb designer start` finds it idle.

## Uninstall

Stop the Designer (`hsb designer stop`), delete `~/.hubsabai` (`%USERPROFILE%\.hubsabai` on
Windows), and remove `~/.hubsabai/bin` from your PATH.

## License

Proprietary, see [LICENSE](LICENSE). Copyright (c) 2026 Datasabai Co., Ltd.
