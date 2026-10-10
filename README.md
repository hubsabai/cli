# Hubsabai CLI

`hsb` is the command-line tool of the Hubsabai SDK: it creates and upgrades integration
workspaces, and starts the Hubsabai Designer that VS Code and AI agents (over MCP) work with.

This repository holds the installers only. The CLI and the Designer are proprietary and are
downloaded from Datasabai's package feeds by the installer.

> **Status:** in preparation, for Datasabai developers only. The installers are not published yet.

## Requirements

- **JDK 25** on `PATH` or in `JAVA_HOME`
- Access to the Hubsabai package feed (Datasabai developers)
- Windows, Linux, or Windows with WSL — install where your workspace files live (inside WSL when
  you work in WSL)

## Install

Coming soon:

```sh
# Linux, WSL, macOS
curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh
```

```powershell
# Windows
irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
```

Then check the machine and create a workspace:

```sh
hsb doctor
hsb workspace init
```

## License

Proprietary — see [LICENSE](LICENSE). Copyright (c) 2026 Datasabai Co., Ltd.
