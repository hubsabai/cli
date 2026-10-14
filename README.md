# Hubsabai CLI

`hsb` is the command-line tool of the Hubsabai SDK: it creates and upgrades integration
workspaces, and runs the Hubsabai Designer that VS Code and AI agents (over MCP) work with.

This repository holds the installers only. The CLI and the Designer are proprietary and are
downloaded from Datasabai's package feeds: the installer fetches `hsb`, and the first
`hsb workspace init`, `clone` or `designer start` fetches the Designer of the same version.

> **Status:** for Datasabai developers only.

## Requirements

Everything below is the same on every system:

- **JDK 25** on `PATH` or in `JAVA_HOME`. The installer checks for it and never installs it;
  [Eclipse Temurin 25](https://adoptium.net/temurin/releases/?version=25) is the one we use.
- **Releases (the default):** a token for the Hubsabai feed, an Azure DevOps personal access
  token with *Packaging: Read*. The installer reads it from `HSB_FEED_TOKEN`, or from
  `~/.m2/settings.xml` (server `hubsabai-sdk` or `hubsabai-maven`, the one your workspaces already
  use), or asks for it. It is never written to disk.
- **Every build of `dev` (`dev` channel):** the Datasabai VPN, no token.

## Install

Pick your system. Install `hsb` where your workspace files live: inside WSL when you work in WSL.

### Windows

PowerShell 5.1 (built into Windows 10 and 11) or PowerShell 7:

```powershell
irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
```

The `dev` channel (VPN):

```powershell
$env:HSB_CHANNEL = "dev"; irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
```

| Parameter | Environment | |
|---|---|---|
| `-Version 1.4.0` | `HSB_VERSION` | a specific version (also how to roll back) |
| `-Channel dev` | `HSB_CHANNEL` | every build of `dev` instead of releases |
| `-NoModifyPath` | `HSB_NO_MODIFY_PATH=1` | don't add `%USERPROFILE%\.hubsabai\bin` to your user PATH |

Installed in `%USERPROFILE%\.hubsabai`. Open a new terminal afterwards.

**"install.ps1 is not digitally signed" or "Run only scripts that you trust".** This only
happens when you run a *downloaded copy* of the script: Windows marks it as coming from the
internet and the default policy (`RemoteSigned`) blocks it. The one-line `irm ... | iex` install
is not a file and is not affected. For a downloaded copy, unblock it once:

```powershell
Unblock-File .\install.ps1
.\install.ps1 -Channel dev
```

or run it for this invocation only, without changing any policy:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Channel dev
```

(`pwsh -ExecutionPolicy Bypass -File ...` in PowerShell 7.)

**`PKIX path building failed` on the dev channel.** Java doesn't trust Datasabai's internal CA
unless it uses the Windows certificate store. The `hsb` launcher does this itself; a build older
than `1.0.100-build284` doesn't, so run
`$env:JAVA_TOOL_OPTIONS = "-Djavax.net.ssl.trustStoreType=Windows-ROOT"` first, or update.

**Uninstall.** `hsb designer stop`, delete `%USERPROFILE%\.hubsabai`, and remove
`%USERPROFILE%\.hubsabai\bin` from your user PATH.

### Linux and macOS

```sh
curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh
```

The `dev` channel (VPN):

```sh
curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | HSB_CHANNEL=dev sh
```

| Option | Environment | |
|---|---|---|
| `--version 1.4.0` | `HSB_VERSION` | a specific version (also how to roll back) |
| `--channel dev` | `HSB_CHANNEL` | every build of `dev` instead of releases |
| `--no-modify-path` | `HSB_NO_MODIFY_PATH=1` | don't add `~/.hubsabai/bin` to your shell startup file |

Installed in `~/.hubsabai`. Open a new terminal afterwards.

**Uninstall.** `hsb designer stop`, delete `~/.hubsabai`, and remove `~/.hubsabai/bin` from your
shell startup file.

### Windows with WSL

Treat WSL as Linux: run the **Linux and macOS** install inside the WSL terminal, and keep your
workspaces on the Linux file system (`~/hubsabai`), not under `/mnt/c`. Windows and WSL share
`localhost`, so only one Designer can use the default port. `hsb doctor` warns when another one
answers from the other side; use one environment per workspace.

## Get started

The same on every system:

```sh
hsb doctor
hsb workspace init                # a new workspace
hsb workspace clone <git url>     # or an existing one
```

The first `init` or `clone` asks once where your workspaces live and remembers it:

| System | Default workspace root |
|---|---|
| Windows | `%USERPROFILE%\hubsabai` (keep it outside OneDrive and out of Documents and Desktop) |
| Linux, macOS, WSL | `~/hubsabai` |

Both then start the Designer if needed and mount the workspace, so the next step is
`code <folder>`. `hsb workspace list` shows your workspaces, `hsb workspace open <name>` opens one.

## What gets installed

```
~/.hubsabai/                    %USERPROFILE%\.hubsabai on Windows
  bin/hsb, bin/hsb.cmd          on your PATH: run the current version
  current                       the version in use
  versions/<version>/bin/       that version's launcher
  versions/<version>/lib/       hsb-cli.jar, and hsb-designer.jar once fetched
  versions/<version>/designer/  Windows: the Designer app, once fetched (instead of the jar)
  config                        your settings (workspace root, Designer idle timeout)
```

The current version and one previous version are kept.

On Windows the Designer comes as an app with its own Java runtime: Task Manager shows it as
"Hubsabai Designer". JDK 25 is still required, for `hsb` itself and to build your workspaces.
`HSB_NO_DESIGNER_IMAGE=1` makes `hsb` use the plain jar instead.

## Update

```sh
hsb update            # newest version of your channel
hsb update --check    # is there one? (installs nothing)
hsb update --to 1.3.0 # a specific version, also how to roll back
```

A running Designer of another version switches the next time it is idle and you run
`hsb designer start`.

The Designer stops by itself after 2 hours without use (never while it is working). Change it
with a line such as `designer.idle-timeout=90m` in `~/.hubsabai/config` (`4h`, `off`, ...); it applies the
next time the Designer starts. `hsb designer status` shows how long it has been idle.

## License

Proprietary, see [LICENSE](LICENSE). Copyright (c) 2026 Datasabai Co., Ltd.
