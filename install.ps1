# Hubsabai CLI installer for Windows: runs on the Windows PowerShell 5.1 every Windows 10/11 ships,
# and on PowerShell 7 (pwsh) when installed.
#
#   irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1))) -Channel dev
#
# Installs the Hubsabai CLI (`hsb`) into %USERPROFILE%\.hubsabai (versions\<v>\, a `current` pointer, a shim in
# %USERPROFILE%\.hubsabai\bin, added to your user PATH), then runs `hsb update --to <v>`, which downloads the
# matching Hubsabai Designer and prunes old versions. No Java is needed: both come with their own runtime.
#
# Working in WSL? Run install.sh inside WSL instead: install hsb where your workspace files live.
#
# HSB_VERSION, HSB_CHANNEL and HSB_NO_MODIFY_PATH=1 do the same as the parameters (handy with irm | iex).
# HSB_FEED_TOKEN is the stable channel's token; otherwise it is read from %USERPROFILE%\.m2\settings.xml
# (server hubsabai-sdk, then hubsabai-maven), otherwise asked for. It is never written to disk.
param(
    [string]$Version = $env:HSB_VERSION,
    [string]$Channel = $(if ($env:HSB_CHANNEL) { $env:HSB_CHANNEL } else { "stable" }),
    [switch]$NoModifyPath = [bool]$env:HSB_NO_MODIFY_PATH
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest's progress bar slows downloads a lot on 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$StableUrl = if ($env:HSB_STABLE_URL) { $env:HSB_STABLE_URL } else { "https://pkgs.dev.azure.com/datasabai/Hubsabai/_packaging/hubsabai-sdk/maven/v1" }
$DevUrl = if ($env:HSB_DEV_URL) { $env:HSB_DEV_URL } else { "https://nexus.datasabai.lan/repository/hubsabai-sdk" }
$GroupPath = "com/datasabai/hsb"
$HomeDir = Join-Path $env:USERPROFILE ".hubsabai"

function Fail([string]$Problem, [string]$Fix) {
    Write-Host "hsb install: $Problem" -ForegroundColor Red
    if ($Fix) { Write-Host "  Fix: $Fix" }
    throw "hsb install failed: $Problem"
}

if ($Channel -notin @("stable", "dev")) { Fail "unknown channel '$Channel'" "use stable or dev" }
if ($Version -like "*-build*") { $Channel = "dev" }
$Base = if ($Channel -eq "dev") { $DevUrl } else { $StableUrl }
$ReachFix = if ($Channel -eq "dev") { "connect to the Datasabai VPN, then run this again" } else { "check your network and your token (Azure DevOps, Packaging: Read)" }

# ------------------------------------------------------------------ token (stable only)

function Get-SettingsToken {
    $Settings = Join-Path $env:USERPROFILE ".m2\settings.xml"
    if (-not (Test-Path $Settings)) { return "" }
    try { [xml]$Xml = Get-Content -Raw $Settings } catch { Fail "can't read $Settings" "fix the file, or set HSB_FEED_TOKEN" }
    foreach ($Id in @("hubsabai-sdk", "hubsabai-maven")) {
        $Server = $Xml.SelectNodes("//*[local-name()='server']") | Where-Object { $_.id -eq $Id } | Select-Object -First 1
        if (-not $Server -or -not $Server.password) { continue }
        $Password = "$($Server.password)".Trim()
        if ($Password -match '^\{.*\}$') { Fail "the token in $Settings is encrypted (Maven settings-security)" "set HSB_FEED_TOKEN to your Azure DevOps token" }
        if ($Password -match '^\$\{env\.([A-Za-z_][A-Za-z0-9_]*)\}$') { $Password = [Environment]::GetEnvironmentVariable($Matches[1]) }
        if ($Password) { return $Password }
    }
    return ""
}

$Headers = @{}
if ($Channel -eq "stable") {
    $Token = if ($env:HSB_FEED_TOKEN) { $env:HSB_FEED_TOKEN } else { Get-SettingsToken }
    if (-not $Token) {
        $Secure = Read-Host "Azure DevOps token (Packaging: Read)" -AsSecureString
        $Bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
        try { $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr) }
        if (-not $Token) { Fail "no token given" "create one in Azure DevOps (User settings > Personal access tokens, Packaging: Read)" }
    }
    $Headers["Authorization"] = "Basic " + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("hsb:$Token"))
}

function Get-File([string]$Url, [string]$OutFile) {
    Invoke-WebRequest -UseBasicParsing -Uri $Url -Headers $Headers -OutFile $OutFile
}

# ------------------------------------------------------------------ version

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("hsb-install-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
    if (-not $Version) {
        try { Get-File "$Base/$GroupPath/hsb-cli/maven-metadata.xml" (Join-Path $Tmp "metadata.xml") }
        catch { Fail "can't read the $Channel channel ($Base)" $ReachFix }
        [xml]$Metadata = Get-Content -Raw (Join-Path $Tmp "metadata.xml")
        $Version = "$($Metadata.metadata.versioning.release)".Trim()
        if (-not $Version) { Fail "no hsb release on the $Channel channel yet" "try -Channel dev" }
    }
    if ($Version -notmatch '^[A-Za-z0-9._-]+$') { Fail "invalid version '$Version'" "pass a version like 1.4.0" }
    Write-Host "Installing Hubsabai CLI $Version ($Channel)"

    # -------------------------------------------------------------- download + verify

    # The CLI as a Windows app-image: hsb.exe with its own Java runtime (a zip with one hsb\ folder).
    $ZipUrl = "$Base/$GroupPath/hsb-cli/$Version/hsb-cli-$Version-windows-x64.zip"
    $Zip = Join-Path $Tmp "hsb-cli.zip"
    try { Get-File $ZipUrl $Zip } catch { Fail "can't download the Hubsabai CLI $Version for Windows" "$ReachFix; check the version with -Version" }
    $Expected = $null
    foreach ($Algorithm in @("SHA256", "SHA1")) {
        try {
            Get-File "$ZipUrl.$($Algorithm.ToLower())" (Join-Path $Tmp "sum")
            $Expected = ((Get-Content -Raw (Join-Path $Tmp "sum")).Trim() -split '\s+')[0]
            break
        } catch { continue }
    }
    if (-not $Expected) { Fail "no checksum published for the Hubsabai CLI $Version" "report it: the installer never installs a file it can't verify" }
    $Actual = (Get-FileHash -Algorithm $Algorithm $Zip).Hash
    if ($Actual -ne $Expected.ToUpper()) { Fail "$Algorithm mismatch for the Hubsabai CLI $Version (expected $Expected, got $Actual)" "run this again; if it persists, report it" }
    Write-Host "  verified ($Algorithm)"

    # -------------------------------------------------------------- install

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Versions = Join-Path $HomeDir "versions"
    $Stage = Join-Path $Versions ".$Version.$PID"
    $Target = Join-Path $Versions $Version
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage "cli"), (Join-Path $HomeDir "bin") | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($Zip, (Join-Path $Stage "cli"))
    $Exe = Join-Path $Stage "cli\hsb\hsb.exe"
    $CliJar = Join-Path $Stage "cli\hsb\app\hsb-cli.jar"
    if (-not (Test-Path $Exe) -or -not (Test-Path $CliJar)) { Fail "the Hubsabai CLI $Version archive is incomplete" "report it" }
    # the PATH shim is a resource of this version's own CLI
    $Jar = [IO.Compression.ZipFile]::OpenRead($CliJar)
    try {
        $Entry = $Jar.GetEntry("hsb-dist/shim/hsb.cmd")
        if (-not $Entry) { Fail "the Hubsabai CLI $Version has no shim" "install a newer version" }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, (Join-Path $Tmp "shim.cmd"), $true)
    } finally { $Jar.Dispose() }
    # replace only the CLI of this version: a Designer already installed beside it stays
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    if (Test-Path (Join-Path $Target "cli")) { Remove-Item -Recurse -Force (Join-Path $Target "cli") }
    Move-Item (Join-Path $Stage "cli") (Join-Path $Target "cli")
    Remove-Item -Recurse -Force $Stage
    Move-Item -Force (Join-Path $Tmp "shim.cmd") (Join-Path $HomeDir "bin\hsb.cmd")
    [IO.File]::WriteAllText((Join-Path $HomeDir "current.tmp"), $Version)
    Move-Item -Force (Join-Path $HomeDir "current.tmp") (Join-Path $HomeDir "current")

    Write-Host "Installed Hubsabai CLI $Version in $HomeDir"

    # -------------------------------------------------------------- PATH

    $Bin = Join-Path $HomeDir "bin"
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $OnPath = ($UserPath -split ';') -contains $Bin
    if (-not $OnPath) {
        if ($NoModifyPath) {
            Write-Host ""
            Write-Host "Add $Bin to your user PATH, then open a new terminal."
        } else {
            [Environment]::SetEnvironmentVariable("Path", (($UserPath.TrimEnd(';') + ";" + $Bin).TrimStart(';')), "User")
            Write-Host "Added $Bin to your user PATH: open a new terminal to use hsb."
        }
    }
    $env:Path = "$Bin;$env:Path"

    # -------------------------------------------------------------- the rest of the version

    # The Hubsabai Designer, and the clean-up of old versions: hsb's own job. The token goes in the environment of
    # that one process, never on a command line or to disk.
    Write-Host ""
    $Hsb = Join-Path $HomeDir "versions\$Version\cli\hsb\hsb.exe"
    $PreviousToken = $env:HSB_FEED_TOKEN
    if ($Channel -eq "stable") { $env:HSB_FEED_TOKEN = $Token }
    # hsb.exe writes UTF-8; Windows PowerShell 5.1 decodes native output with the OEM codepage (437), which turns
    # the check marks into "Γ£ô". Decode as UTF-8 for these calls, then restore.
    $PreviousEncoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
    try { & $Hsb update --to $Version } finally { $env:HSB_FEED_TOKEN = $PreviousToken }
    if ($LASTEXITCODE -ne 0) {
        try { [Console]::OutputEncoding = $PreviousEncoding } catch { }
        Fail "the Hubsabai Designer $Version was not installed" "run: hsb update --to $Version"
    }

    Write-Host ""
    try { & (Join-Path $Bin "hsb.cmd") doctor } finally { try { [Console]::OutputEncoding = $PreviousEncoding } catch { } }
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
