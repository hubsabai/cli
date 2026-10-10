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

| install.sh | install.ps1 | environment | |
|---|---|---|---|
| `--version 1.4.0` | `-Version 1.4.0` | `HSB_VERSION` | a specific version (also how to roll back) |
| `--channel dev` | `-Channel dev` | `HSB_CHANNEL` | every build of `dev` instead of releases (needs the Datasabai VPN) |
| `--no-modify-path` | `-NoModifyPath` | `HSB_NO_MODIFY_PATH=1` | don't add `~/.hubsabai/bin` to your PATH (shell startup file, or Windows user PATH) |

The environment variables are the easy way with a one-line install:

```sh
curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | HSB_CHANNEL=dev sh
```

```powershell
$env:HSB_CHANNEL = "dev"; irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
```

The Windows installer runs on the Windows PowerShell 5.1 built into Windows 10 and 11, and on
PowerShell 7 if you have it.

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
