# Hubsabai CLI installer for Windows (PowerShell 5.1 or 7).
#
#   irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1))) -Channel dev
#
# Installs `hsb` into %USERPROFILE%\.hubsabai (versions\<v>\, a `current` pointer, shims in
# %USERPROFILE%\.hubsabai\bin, added to your user PATH). The Hubsabai Designer is not downloaded
# here: `hsb designer start` fetches the one matching hsb.
#
# Working in WSL? Run install.sh inside WSL instead: install hsb where your workspace files live.
#
# HSB_FEED_TOKEN is the stable channel's token; otherwise it is read from %USERPROFILE%\.m2\settings.xml
# (server hubsabai-sdk, then hubsabai-maven), otherwise asked for. It is never written to disk.
param(
    [string]$Version = "",
    [ValidateSet("stable", "dev")][string]$Channel = "stable",
    [switch]$NoModifyPath
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest's progress bar slows downloads a lot on 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$StableUrl = if ($env:HSB_STABLE_URL) { $env:HSB_STABLE_URL } else { "https://pkgs.dev.azure.com/datasabai/Hubsabai/_packaging/hubsabai-sdk/maven/v1" }
$DevUrl = if ($env:HSB_DEV_URL) { $env:HSB_DEV_URL } else { "https://nexus.datasabai.lan/repository/hubsabai-sdk" }
$GroupPath = "com/datasabai/hsb"
$JavaFeature = 25
$Keep = 2
$HomeDir = Join-Path $env:USERPROFILE ".hubsabai"

function Fail([string]$Problem, [string]$Fix) {
    Write-Host "hsb install: $Problem" -ForegroundColor Red
    if ($Fix) { Write-Host "  Fix: $Fix" }
    throw "hsb install failed: $Problem"
}

if ($Version -like "*-build*") { $Channel = "dev" }
$Base = if ($Channel -eq "dev") { $DevUrl } else { $StableUrl }
$ReachFix = if ($Channel -eq "dev") { "connect to the Datasabai VPN, then run this again" } else { "check your network and your token (Azure DevOps, Packaging: Read)" }

# ------------------------------------------------------------------ Java

$Java = if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME "bin\java.exe"))) { Join-Path $env:JAVA_HOME "bin\java.exe" } else { "java" }
if (-not (Get-Command $Java -ErrorAction SilentlyContinue)) {
    Fail "Java $JavaFeature is not installed" "install JDK $JavaFeature (e.g. winget install EclipseAdoptium.Temurin.$JavaFeature.JDK) and open a new terminal"
}
$JavaLine = (& $Java -version 2>&1 | Select-Object -First 1 | Out-String)
$JavaVersion = if ($JavaLine -match 'version "(\d+)') { [int]$Matches[1] } else { 0 }
if ($JavaVersion -lt $JavaFeature) {
    Fail "Java $JavaVersion found, hsb needs $JavaFeature or newer" "install JDK $JavaFeature and put it first on PATH (or set JAVA_HOME)"
}

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
        $Token = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure))
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
    Write-Host "Installing hsb $Version ($Channel)"

    # -------------------------------------------------------------- download + verify

    $JarUrl = "$Base/$GroupPath/hsb-cli/$Version/hsb-cli-$Version.jar"
    $Jar = Join-Path $Tmp "hsb-cli.jar"
    try { Get-File $JarUrl $Jar } catch { Fail "can't download hsb-cli $Version" "$ReachFix; check the version with -Version" }
    $Expected = $null
    foreach ($Algorithm in @("SHA256", "SHA1")) {
        try {
            Get-File "$JarUrl.$($Algorithm.ToLower())" (Join-Path $Tmp "sum")
            $Expected = ((Get-Content -Raw (Join-Path $Tmp "sum")).Trim() -split '\s+')[0]
            break
        } catch { continue }
    }
    if (-not $Expected) { Fail "no checksum published for hsb-cli $Version" "report it: the installer never installs a jar it can't verify" }
    $Actual = (Get-FileHash -Algorithm $Algorithm $Jar).Hash
    if ($Actual -ne $Expected.ToUpper()) { Fail "$Algorithm mismatch for hsb-cli $Version (expected $Expected, got $Actual)" "run this again; if it persists, report it" }
    Write-Host "  verified ($Algorithm)"

    # -------------------------------------------------------------- install

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Versions = Join-Path $HomeDir "versions"
    $Stage = Join-Path $Versions ".$Version.$PID"
    $Target = Join-Path $Versions $Version
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
    New-Item -ItemType Directory -Force -Path (Join-Path $Stage "lib"), (Join-Path $Stage "bin"), (Join-Path $HomeDir "bin") | Out-Null
    Copy-Item $Jar (Join-Path $Stage "lib\hsb-cli.jar")
    $Fetched = Join-Path $Target "lib\hsb-designer.jar"
    if (Test-Path $Fetched) { Copy-Item $Fetched (Join-Path $Stage "lib") }   # keep a Designer already fetched
    $Zip = [IO.Compression.ZipFile]::OpenRead($Jar)
    try {
        $Entries = @{
            "hsb-dist/bin/hsb.cmd"  = Join-Path $Stage "bin\hsb.cmd"
            "hsb-dist/bin/hsb"      = Join-Path $Stage "bin\hsb"
            "hsb-dist/shim/hsb.cmd" = Join-Path $Tmp "shim.cmd"
        }
        foreach ($Name in $Entries.Keys) {
            $Entry = $Zip.GetEntry($Name)
            if (-not $Entry) { Fail "hsb-cli $Version has no $Name" "install a newer version" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Entries[$Name], $true)
        }
    } finally { $Zip.Dispose() }
    if (Test-Path $Target) { Remove-Item -Recurse -Force $Target }
    Move-Item $Stage $Target
    Move-Item -Force (Join-Path $Tmp "shim.cmd") (Join-Path $HomeDir "bin\hsb.cmd")
    [IO.File]::WriteAllText((Join-Path $HomeDir "current.tmp"), $Version)
    Move-Item -Force (Join-Path $HomeDir "current.tmp") (Join-Path $HomeDir "current")

    # keep the current version and the newest other one (hsb update --to <previous> rolls back)
    Get-ChildItem -Directory $Versions | Where-Object { $_.Name -ne $Version -and -not $_.Name.StartsWith(".") } |
        Sort-Object { [regex]::Replace($_.Name, '\d+', { $args[0].Value.PadLeft(10, '0') }) } -Descending |
        Select-Object -Skip ($Keep - 1) |
        ForEach-Object { Remove-Item -Recurse -Force $_.FullName; Write-Host "  removed $($_.Name)" }

    Write-Host "Installed hsb $Version in $HomeDir"

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

    # -------------------------------------------------------------- check

    Write-Host ""
    & (Join-Path $Bin "hsb.cmd") doctor
    Write-Host ""
    Write-Host "Next: hsb workspace init   (hsb designer start downloads the Designer on first use)"
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
