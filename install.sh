#!/bin/sh
# Hubsabai CLI installer for Linux, WSL and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh -s -- --channel dev
#
# POSIX sh (dash, bash, zsh, busybox, macOS sh). Everything runs from main() at the very end, so a
# download cut short runs nothing.
#
# Installs `hsb` into ~/.hubsabai (versions/<v>/, a `current` pointer, shims in ~/.hubsabai/bin).
# The Hubsabai Designer is not downloaded here: `hsb designer start` fetches the one matching hsb.
#
# Options:
#   --version <v>     install this version (default: the newest of the channel)
#   --channel <name>  stable (releases, default) or dev (every build, needs the Datasabai VPN)
#   --no-modify-path  don't add ~/.hubsabai/bin to PATH in your shell's startup file
#   -h, --help        show this help
#
# Environment (handy with `curl | sh`):
#   HSB_VERSION, HSB_CHANNEL, HSB_NO_MODIFY_PATH=1   same as the options
#   HSB_FEED_TOKEN    token for the stable channel; otherwise read from ~/.m2/settings.xml
#                     (server hubsabai-sdk, then hubsabai-maven), otherwise asked for.
#
# The token is never written to disk and never passed on a command line.
set -eu

STABLE_URL=${HSB_STABLE_URL:-https://pkgs.dev.azure.com/datasabai/Hubsabai/_packaging/hubsabai-sdk/maven/v1}
DEV_URL=${HSB_DEV_URL:-https://nexus.datasabai.lan/repository/hubsabai-sdk}
GROUP_PATH=com/datasabai/hsb
JAVA_FEATURE=25
KEEP=2

home_dir="$HOME/.hubsabai"
version=${HSB_VERSION:-}
channel=${HSB_CHANNEL:-stable}
modify_path=1
[ -n "${HSB_NO_MODIFY_PATH:-}" ] && modify_path=0
tmp=""

main() {

say() { printf '%s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() {
  printf 'hsb install: %s\n' "$1" >&2
  [ -n "${2:-}" ] && printf '  Fix: %s\n' "$2" >&2
  exit 1
}
usage() {
  cat <<'EOF'
Hubsabai CLI installer for Linux, WSL and macOS.

  curl -fsSL https://raw.githubusercontent.com/hubsabai/cli/main/install.sh | sh -s -- [options]

  --version <v>     install this version (default: the newest of the channel)
  --channel <name>  stable (releases, default) or dev (every build, needs the Datasabai VPN)
  --no-modify-path  don't add ~/.hubsabai/bin to PATH in your shell's startup file
  -h, --help        show this help

HSB_VERSION, HSB_CHANNEL and HSB_NO_MODIFY_PATH=1 do the same as the options.
HSB_FEED_TOKEN is the stable channel's token; otherwise it is read from ~/.m2/settings.xml
(server hubsabai-sdk, then hubsabai-maven), otherwise asked for.
EOF
}
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT INT TERM

while [ $# -gt 0 ]; do
  case $1 in
    --version) version=${2:?--version needs a value}; shift 2 ;;
    --version=*) version=${1#--version=}; shift ;;
    --channel) channel=${2:?--channel needs a value}; shift 2 ;;
    --channel=*) channel=${1#--channel=}; shift ;;
    --no-modify-path) modify_path=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown option: $1" "see --help" ;;
  esac
done

case $channel in
  stable) base=$STABLE_URL ;;
  dev) base=$DEV_URL ;;
  *) fail "unknown channel '$channel'" "use --channel stable or --channel dev" ;;
esac
[ -n "$version" ] && case $version in
  *-build*) [ "$channel" = dev ] || { channel=dev; base=$DEV_URL; } ;;
esac

# ---------------------------------------------------------------- preflight

case $(uname -s) in
  Linux|Darwin) ;;
  MINGW*|MSYS*|CYGWIN*)
    fail "this is the Linux/macOS installer" \
      "on Windows run in PowerShell: irm https://raw.githubusercontent.com/hubsabai/cli/main/install.ps1 | iex" ;;
  *) fail "unsupported system: $(uname -s)" "use Linux, WSL, macOS or Windows" ;;
esac

command -v curl >/dev/null 2>&1 || fail "curl is not installed" "install curl, then run this again"

java_bin=java
[ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ] && java_bin=$JAVA_HOME/bin/java
command -v "$java_bin" >/dev/null 2>&1 \
  || fail "Java $JAVA_FEATURE is not installed" "install JDK $JAVA_FEATURE (e.g. sdk install java $JAVA_FEATURE-tem) and put it on PATH"
java_version=$("$java_bin" -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)
[ -n "$java_version" ] && [ "$java_version" -ge "$JAVA_FEATURE" ] \
  || fail "Java ${java_version:-?} found, hsb needs $JAVA_FEATURE or newer" "install JDK $JAVA_FEATURE and put it first on PATH (or set JAVA_HOME)"

if command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1" | cut -d' ' -f1; }
else sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }; fi
if command -v sha1sum >/dev/null 2>&1; then sha1() { sha1sum "$1" | cut -d' ' -f1; }
else sha1() { shasum -a 1 "$1" | cut -d' ' -f1; }; fi

# ---------------------------------------------------------------- token (stable only)

token=""
settings_token() {
  settings=$HOME/.m2/settings.xml
  [ -f "$settings" ] || return 0
  for id in hubsabai-sdk hubsabai-maven; do
    found=$(tr -d '\r\n' < "$settings" \
      | sed 's#</server>#&\
#g' \
      | grep "<id>[[:space:]]*$id[[:space:]]*</id>" \
      | sed -n 's#.*<password>[[:space:]]*\([^<]*[^<[:space:]]\)[[:space:]]*</password>.*#\1#p' \
      | head -n 1) || true
    if [ -n "$found" ]; then
      case $found in
        \{*\}) fail "the token in $settings is encrypted (Maven settings-security)" "set HSB_FEED_TOKEN to your Azure DevOps token" ;;
        \$\{env.*\})
          name=${found#\$\{env.}; name=${name%\}}
          found=$(printenv "$name" || true) ;;
      esac
      [ -n "$found" ] && { printf '%s' "$found"; return 0; }
    fi
  done
}
if [ "$channel" = stable ]; then
  token=${HSB_FEED_TOKEN:-}
  [ -n "$token" ] || token=$(settings_token)
  if [ -z "$token" ]; then
    [ -r /dev/tty ] || fail "no token for the Hubsabai feed" "set HSB_FEED_TOKEN, or add it to ~/.m2/settings.xml"
    printf 'Azure DevOps token (Packaging: Read): ' > /dev/tty
    stty -echo < /dev/tty 2>/dev/null || true
    IFS= read -r token < /dev/tty || true
    stty echo < /dev/tty 2>/dev/null || true
    printf '\n' > /dev/tty
    [ -n "$token" ] || fail "no token given" "create one in Azure DevOps (User settings > Personal access tokens, Packaging: Read)"
  fi
fi

# fetch <url> <file>: GET, credentials read by curl from stdin, never from its arguments.
fetch() {
  set -- "$1" "$2" -fsSL --retry 2
  case $1 in https://*) set -- "$@" --proto '=https' --tlsv1.2 ;; esac # never downgrade off HTTPS
  url=$1; out=$2; shift 2
  if [ -n "$token" ]; then
    printf 'user = "hsb:%s"\n' "$token" | curl "$@" -K - -o "$out" "$url"
  else
    curl "$@" -o "$out" "$url"
  fi
}
reach_fix() {
  if [ "$channel" = dev ]; then echo "connect to the Datasabai VPN, then run this again"
  else echo "check your network and your token (Azure DevOps, Packaging: Read)"; fi
}

# ---------------------------------------------------------------- version

tmp=$(mktemp -d "${TMPDIR:-/tmp}/hsb-install.XXXXXX")
if [ -z "$version" ]; then
  fetch "$base/$GROUP_PATH/hsb-cli/maven-metadata.xml" "$tmp/metadata.xml" \
    || fail "can't read the $channel channel ($base)" "$(reach_fix)"
  version=$(tr -d '\r\n' < "$tmp/metadata.xml" | sed -n 's#.*<release>[[:space:]]*\([^<]*[^<[:space:]]\)[[:space:]]*</release>.*#\1#p')
  [ -n "$version" ] || fail "no hsb release on the $channel channel yet" "try --channel dev"
fi
case $version in
  *[!A-Za-z0-9._-]*|"") fail "invalid version '$version'" "pass a version like 1.4.0" ;;
esac

say "Installing hsb $version ($channel)"

# ---------------------------------------------------------------- download + verify

jar_url="$base/$GROUP_PATH/hsb-cli/$version/hsb-cli-$version.jar"
fetch "$jar_url" "$tmp/hsb-cli.jar" || fail "can't download hsb-cli $version" "$(reach_fix); check the version with --version"
if fetch "$jar_url.sha256" "$tmp/sum" 2>/dev/null; then
  expected=$(cut -d' ' -f1 < "$tmp/sum" | tr -d '\r\n' | tr 'A-F' 'a-f'); actual=$(sha256 "$tmp/hsb-cli.jar"); algorithm=SHA-256
elif fetch "$jar_url.sha1" "$tmp/sum" 2>/dev/null; then
  expected=$(cut -d' ' -f1 < "$tmp/sum" | tr -d '\r\n' | tr 'A-F' 'a-f'); actual=$(sha1 "$tmp/hsb-cli.jar"); algorithm=SHA-1
else
  fail "no checksum published for hsb-cli $version" "report it: the installer never installs a jar it can't verify"
fi
[ "$expected" = "$actual" ] || fail "$algorithm mismatch for hsb-cli $version (expected $expected, got $actual)" "run this again; if it persists, report it"
info "verified ($algorithm)"

# ---------------------------------------------------------------- install

extract() { # extract <entry> <target>
  if command -v unzip >/dev/null 2>&1; then
    unzip -p "$tmp/hsb-cli.jar" "$1" > "$2"
  else
    (cd "$tmp" && rm -rf x && mkdir x && cd x && jar xf ../hsb-cli.jar "$1" && cat "$1") > "$2"
  fi
  [ -s "$2" ] || fail "hsb-cli $version has no $1" "install a newer version"
}

stage="$home_dir/versions/.$version.$$"
rm -rf "$stage"
mkdir -p "$stage/lib" "$stage/bin" "$home_dir/bin"
cp "$tmp/hsb-cli.jar" "$stage/lib/hsb-cli.jar"
if [ -f "$home_dir/versions/$version/lib/hsb-designer.jar" ]; then
  cp "$home_dir/versions/$version/lib/hsb-designer.jar" "$stage/lib/" # keep a Designer already fetched
fi
extract hsb-dist/bin/hsb "$stage/bin/hsb"
extract hsb-dist/bin/hsb.cmd "$stage/bin/hsb.cmd"
extract hsb-dist/shim/hsb "$tmp/shim"
chmod 755 "$stage/bin/hsb" "$tmp/shim"
rm -rf "$home_dir/versions/$version"
mv "$stage" "$home_dir/versions/$version"
mv -f "$tmp/shim" "$home_dir/bin/hsb"
printf '%s' "$version" > "$home_dir/current.tmp"
mv -f "$home_dir/current.tmp" "$home_dir/current"

# keep the current version and the newest other one (hsb update --to <previous> rolls back)
ls -1t "$home_dir/versions" | grep -v '^\.' | grep -vxF "$version" | tail -n +"$KEEP" \
  | while IFS= read -r old; do rm -rf "$home_dir/versions/$old"; info "removed $old"; done

say "Installed hsb $version in $home_dir"

# ---------------------------------------------------------------- PATH

on_path=0
case ":$PATH:" in *":$home_dir/bin:"*) on_path=1 ;; esac
if [ $on_path -eq 0 ]; then
  shell_name=$(basename "${SHELL:-sh}")
  case $shell_name in
    fish) line="fish_add_path $home_dir/bin"; rc="$HOME/.config/fish/config.fish" ;;
    zsh) line="export PATH=\"$home_dir/bin:\$PATH\""; rc="$HOME/.zshrc" ;;
    bash) line="export PATH=\"$home_dir/bin:\$PATH\""; rc="$HOME/.bashrc" ;;
    *) line="export PATH=\"$home_dir/bin:\$PATH\""; rc="$HOME/.profile" ;;
  esac
  if [ $modify_path -eq 1 ]; then
    mkdir -p "$(dirname "$rc")"
    grep -qsF "$line" "$rc" || printf '\n# Hubsabai CLI\n%s\n' "$line" >> "$rc"
    say "Added $home_dir/bin to PATH in $rc: open a new terminal to use hsb."
  else
    say ""
    say "Add hsb to your PATH (in $rc), then open a new terminal:"
    say "  $line"
  fi
fi

# ---------------------------------------------------------------- check

say ""
"$home_dir/bin/hsb" doctor || true
say ""
say "Next: hsb workspace init   (hsb designer start downloads the Designer on first use)"
}

main "$@"
