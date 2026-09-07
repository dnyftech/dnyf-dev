#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
USR_LOCAL="$ROOT/usr/local"
BIN="$ROOT/bin"
ETC="$ROOT/etc/dnyf"
CONFIG="$ROOT/config"
DOCS="$ROOT/docs"

printf '\033[1;36m============================================================\033[0m\n'
printf '\033[1;36m DNYF-DEV FOUNDATION + VISUAL SYSTEM REPAIR\033[0m\n'
printf '\033[1;36m============================================================\033[0m\n'

mkdir -p \
  "$ROOT/etc/dnyf/theme" \
  "$ROOT/etc/dnyf/icons" \
  "$ROOT/etc/dnyf/colors" \
  "$ROOT/etc/dnyf/file-types" \
  "$ROOT/etc/dnyf/archive" \
  "$ROOT/config/theme" \
  "$ROOT/config/icons" \
  "$ROOT/config/colors" \
  "$ROOT/docs/theme" \
  "$ROOT/usr/share/dnyf/theme" \
  "$ROOT/usr/share/dnyf/icons"

###############################################################################
# 1. FIX VALIDATOR — REMOVE PYTHON DEPENDENCY
###############################################################################

VALIDATOR="$ROOT/scripts/validate.sh"

if [ -f "$VALIDATOR" ]; then
    cp "$VALIDATOR" "$VALIDATOR.before-no-python.$(date +%Y%m%d%H%M%S)"
fi

cat > "$VALIDATOR" <<'VALIDATE'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

GREEN='\033[1;32m'
RED='\033[1;31m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

OK() {
    printf "${GREEN}[OK]${RESET}   %s\n" "$1"
}

FAIL() {
    printf "${RED}[FAIL]${RESET} %s\n" "$1"
    FAILED=1
}

FAILED=0

printf "\n"
printf "${CYAN}============================================================${RESET}\n"
printf "${CYAN} DNYF-DEV FILESYSTEM VALIDATION${RESET}\n"
printf "${CYAN}============================================================${RESET}\n"

# Identity
[ -f "$ROOT/etc/os-release" ] \
    && grep -q 'NAME="DNYF OS"' "$ROOT/etc/os-release" \
    && OK "DNYF OS identity" \
    || FAIL "DNYF OS identity"

DEVICE_ID="$(cat "$ROOT/etc/dnyf/device-id" 2>/dev/null || true)"

[ "$DEVICE_ID" = "cbd06be57a51cb84e12b4e112a4d06e9" ] \
    && OK "canonical device ID" \
    || FAIL "canonical device ID"

[ -f "$ROOT/etc/dnyf/identity.json" ] \
    && OK "identity metadata" \
    || FAIL "identity metadata"

[ -f "$ROOT/etc/dnyf/platform.json" ] \
    && OK "platform metadata" \
    || FAIL "platform metadata"

[ -f "$ROOT/etc/dnyf/capabilities.json" ] \
    && OK "capability registry" \
    || FAIL "capability registry"

[ -f "$ROOT/etc/dnyf/security-policy.json" ] \
    && OK "security policy" \
    || FAIL "security policy"

[ -f "$ROOT/etc/dnyf/auth/protocol.json" ] \
    && OK "cryptographic auth protocol" \
    || FAIL "cryptographic auth protocol"

[ -f "$ROOT/etc/dnyf/pairing/config.json" ] \
    && OK "pairing configuration" \
    || FAIL "pairing configuration"

[ -f "$ROOT/etc/dnyf/pairing/session-protocol.json" ] \
    && OK "session protocol" \
    || FAIL "session protocol"

[ -f "$ROOT/etc/dnyf/sync/config.json" ] \
    && OK "sync configuration" \
    || FAIL "sync configuration"

[ -f "$ROOT/etc/dnyf/trust/peers.json" ] \
    && OK "trust registry" \
    || FAIL "trust registry"

[ -f "$ROOT/registry/services.json" ] \
    && OK "service registry" \
    || FAIL "service registry"

[ -f "$ROOT/etc/dnyf/phase-manifest.json" ] \
    && OK "phase manifest" \
    || FAIL "phase manifest"

[ -f "$ROOT/etc/dnyf/transfer/protocol.json" ] \
    && OK "transfer protocol" \
    || FAIL "transfer protocol"

[ -x "$ROOT/bin/dnyf" ] \
    && OK "DNYF CLI" \
    || FAIL "DNYF CLI"

# Trust registry policy — pure shell, no Python.
TRUST="$ROOT/etc/dnyf/trust/peers.json"

if [ -f "$TRUST" ]; then

    TRUST_LOCAL="$(sed -n \
        's/.*"local_device_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$TRUST" | head -n 1)"

    SELF_TRUST="$(sed -n \
        's/.*"self_trust"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' \
        "$TRUST" | head -n 1)"

    PEERS_EMPTY=0

    if grep -q '"peers"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' "$TRUST"; then
        PEERS_EMPTY=1
    fi

    if [ "$TRUST_LOCAL" = "$DEVICE_ID" ] &&
       [ "$SELF_TRUST" = "false" ] &&
       [ "$PEERS_EMPTY" = "1" ]; then
        OK "trust registry policy"
    else
        FAIL "trust registry policy"
    fi

else
    FAIL "trust registry policy"
fi

###############################################################################
# VISUAL SYSTEM
###############################################################################

[ -f "$ROOT/etc/dnyf/theme/theme.json" ] \
    && OK "DNYF visual theme" \
    || FAIL "DNYF visual theme"

[ -f "$ROOT/etc/dnyf/colors/dircolors" ] \
    && OK "directory/file colors" \
    || FAIL "directory/file colors"

[ -f "$ROOT/etc/dnyf/icons/icons.json" ] \
    && OK "icon registry" \
    || FAIL "icon registry"

[ -f "$ROOT/etc/dnyf/archive/archive-theme.json" ] \
    && OK "archive/ZIP visual metadata" \
    || FAIL "archive/ZIP visual metadata"

###############################################################################
# DIRECTORY STRUCTURE
###############################################################################

for DIR in \
    apps backups bin config docs engines home logs packages registry scripts \
    system tooling var workspace opt/dnyf etc/dnyf usr/local/bin
do
    [ -d "$ROOT/$DIR" ] \
        && OK "directory: $DIR" \
        || FAIL "directory: $DIR"
done

###############################################################################
# SECURITY INVARIANTS
###############################################################################

if grep -q '"self_trust"[[:space:]]*:[[:space:]]*false' "$TRUST"; then
    OK "self-trust disabled"
else
    FAIL "self-trust disabled"
fi

if grep -q '"automatic_trust"[[:space:]]*:[[:space:]]*false' \
    "$ROOT/etc/dnyf/pairing/config.json"; then
    OK "automatic trust disabled"
else
    FAIL "automatic trust disabled"
fi

if grep -q '"self_pairing"[[:space:]]*:[[:space:]]*false' \
    "$ROOT/etc/dnyf/pairing/config.json"; then
    OK "self-pairing disabled"
else
    FAIL "self-pairing disabled"
fi

printf "\n${CYAN}============================================================${RESET}\n"

if [ "$FAILED" -eq 0 ]; then
    printf "${GREEN} VALIDATION: PASS${RESET}\n"
    printf "${GREEN} DNYF-DEV FOUNDATION IS VALID${RESET}\n"
else
    printf "${RED} VALIDATION: FAIL${RESET}\n"
    exit 1
fi

printf "${CYAN}============================================================${RESET}\n"
VALIDATE

chmod +x "$VALIDATOR"

###############################################################################
# 2. DNYF VISUAL THEME
###############################################################################

cat > "$ROOT/etc/dnyf/theme/theme.json" <<'JSON'
{
  "schema": "dnyf.theme.v1",
  "name": "DNYFTECH Developer",
  "brand": "DNYFTECH",
  "platform": "DNYF OS",
  "runtime": "DNYF-DEV",
  "accent": "cyan",
  "primary": "cyan",
  "secondary": "blue",
  "success": "green",
  "warning": "yellow",
  "error": "red",
  "info": "cyan",
  "muted": "bright_black",
  "text": "white",
  "background": "black",
  "font": "JetBrains Mono",
  "ui_font": "Syne",
  "terminal": {
    "bold": true,
    "truecolor": true,
    "unicode": true
  }
}
JSON

cp "$ROOT/etc/dnyf/theme/theme.json" \
   "$ROOT/config/theme/theme.json"

cp "$ROOT/etc/dnyf/theme/theme.json" \
   "$ROOT/usr/share/dnyf/theme/theme.json"

###############################################################################
# 3. TERMINAL DIRECTORY + FILE COLORS
###############################################################################

cat > "$ROOT/etc/dnyf/colors/dircolors" <<'DIRCOLORS'
# DNYFTECH / DNYF OS directory and file color policy

# Directories
DIR 01;36

# Executables
EXEC 01;32

# Symbolic links
LINK 01;35

# Archives
.tar 01;31
.tar.gz 01;31
.tgz 01;31
.zip 01;31
.7z 01;31
.rar 01;31

# Source
.js 01;33
.jsx 01;33
.ts 01;33
.tsx 01;33
.py 01;33
.java 01;33
.c 01;33
.cpp 01;33
.h 01;33
.hpp 01;33
.rs 01;33
.go 01;33
.sh 01;32

# Web
.html 01;34
.css 01;34
.json 01;36
.xml 01;34
.svg 01;35

# Documentation
.md 01;37
.txt 00;37
.pdf 01;31

# Configuration
.conf 01;36
.config 01;36
.env 01;31
.yaml 01;36
.yml 01;36

# Images
.png 01;35
.jpg 01;35
.jpeg 01;35
.webp 01;35
.gif 01;35

# Logs
.log 00;33

# DNYF system files
.dnyf 01;36
.dnyf.json 01;36
DNYF

cp "$ROOT/etc/dnyf/colors/dircolors" \
   "$ROOT/config/colors/dircolors"

###############################################################################
# 4. ICON REGISTRY
###############################################################################

cat > "$ROOT/etc/dnyf/icons/icons.json" <<'JSON'
{
  "schema": "dnyf.icons.v1",
  "set": "DNYFTECH Developer",
  "unicode": true,
  "icons": {
    "root": "◆",
    "dnyf": "◈",
    "os": "▣",
    "workspace": "▤",
    "project": "▰",
    "app": "▱",
    "engine": "⚙",
    "ai": "✦",
    "model": "◉",
    "config": "⚙",
    "security": "⛨",
    "identity": "◎",
    "device": "▣",
    "network": "⌁",
    "server": "▥",
    "service": "●",
    "terminal": "›_",
    "script": "▶",
    "source": "◇",
    "folder": "▰",
    "file": "▱",
    "archive": "▤",
    "zip": "▥",
    "database": "▦",
    "log": "≡",
    "documentation": "▧",
    "warning": "⚠",
    "success": "✓",
    "error": "✗",
    "info": "ℹ",
    "lock": "🔒",
    "sync": "⇄",
    "upload": "↑",
    "download": "↓",
    "link": "↗",
    "cloud": "☁",
    "android": "▣",
    "windows": "⊞",
    "linux": "◉",
    "macos": "●"
  }
}
JSON

cp "$ROOT/etc/dnyf/icons/icons.json" \
   "$ROOT/config/icons/icons.json"

cp "$ROOT/etc/dnyf/icons/icons.json" \
   "$ROOT/usr/share/dnyf/icons/icons.json"

###############################################################################
# 5. ARCHIVE / ZIP VISUAL METADATA
###############################################################################

cat > "$ROOT/etc/dnyf/archive/archive-theme.json" <<'JSON'
{
  "schema": "dnyf.archive-theme.v1",
  "archive_formats": [
    "zip",
    "tar",
    "tar.gz",
    "tgz",
    "7z"
  ],
  "icon": "▤",
  "color": "red",
  "label": "DNYF Archive",
  "zip": {
    "extension": ".zip",
    "color_code": "01;31",
    "icon": "▥"
  },
  "backup": {
    "color_code": "01;35",
    "icon": "▤"
  }
}
JSON

###############################################################################
# 6. DNYF VISUAL COMMAND
###############################################################################

cat > "$ROOT/bin/dnyf-theme" <<'THEME'
#!/data/data/com.termux/files/usr/bin/bash

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

CYAN='\033[1;36m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
RESET='\033[0m'

case "${1:-show}" in

show)
    printf "\n"
    printf "${CYAN}◆ DNYFTECH${RESET} ${WHITE}Developer Environment${RESET}\n"
    printf "${BLUE}◈ DNYF-DEV${RESET} ${WHITE}Filesystem${RESET}\n"
    printf "\n"

    printf "${CYAN}▰${RESET} apps       "
    printf "${CYAN}▰${RESET} workspace  "
    printf "${MAGENTA}✦${RESET} engines    "
    printf "${YELLOW}⚙${RESET} config\n"

    printf "${GREEN}✓${RESET} validated   "
    printf "${RED}▤${RESET} archives    "
    printf "${MAGENTA}◎${RESET} identity   "
    printf "${BLUE}⌁${RESET} network\n"

    printf "\n"
    ;;

paths)
    printf '%s\n' "$ROOT/etc/dnyf/theme/theme.json"
    printf '%s\n' "$ROOT/etc/dnyf/colors/dircolors"
    printf '%s\n' "$ROOT/etc/dnyf/icons/icons.json"
    printf '%s\n' "$ROOT/etc/dnyf/archive/archive-theme.json"
    ;;

*)
    echo "Usage: dnyf-theme [show|paths]"
    exit 1
    ;;
esac
THEME

chmod +x "$ROOT/bin/dnyf-theme"

ln -sf "$ROOT/bin/dnyf-theme" "$USR_LOCAL/bin/dnyf-theme"
ln -sf "$ROOT/bin/dnyf-theme" "$ROOT/usr/bin/dnyf-theme"

###############################################################################
# 7. DNYF ZIP / ARCHIVE NAMING POLICY
###############################################################################

cat > "$ROOT/docs/theme/ARCHIVE-NAMING.md" <<'DOC'
# DNYFTECH Archive Naming

DNYF archives use:

DNYF-<SYSTEM>-<COMPONENT>-<VERSION>-<DATE>.zip

Examples:

DNYF-DEV-FULL-1.0.0-20260907.zip
DNYF-OS-PHASE8-1.0.0-20260907.zip
DNYF-CEEZIX-RUNTIME-1.0.0-20260907.zip

Archive visual identity:

Icon: ▤ / ▥
Primary terminal color: red
Backup color: magenta
Validated archive: green status marker
Corrupt/failed archive: red status marker
DOC

###############################################################################
# 8. VISUAL ENVIRONMENT EXPORT
###############################################################################

cat > "$ROOT/etc/dnyf/theme/env.sh" <<'ENV'
# DNYFTECH visual environment

export DNYF_THEME="DNYFTECH Developer"
export DNYF_ACCENT="cyan"
export DNYF_FONT="JetBrains Mono"
export DNYF_UI_FONT="Syne"

export DNYF_COLOR_ROOT="\033[1;36m"
export DNYF_COLOR_FOLDER="\033[1;36m"
export DNYF_COLOR_FILE="\033[0;37m"
export DNYF_COLOR_EXEC="\033[1;32m"
export DNYF_COLOR_ARCHIVE="\033[1;31m"
export DNYF_COLOR_CONFIG="\033[1;36m"
export DNYF_COLOR_SOURCE="\033[1;33m"
export DNYF_COLOR_ERROR="\033[1;31m"
export DNYF_COLOR_WARNING="\033[1;33m"
export DNYF_COLOR_SUCCESS="\033[1;32m"
export DNYF_COLOR_INFO="\033[1;36m"
export DNYF_COLOR_ICON="\033[1;35m"
export DNYF_COLOR_RESET="\033[0m"
ENV

###############################################################################
# 9. README
###############################################################################

cat > "$ROOT/docs/theme/README.md" <<'DOC'
# DNYFTECH Visual Identity System

The DNYF-DEV filesystem has a dedicated visual metadata layer.

Components:

- `etc/dnyf/theme/` — global theme
- `etc/dnyf/colors/` — terminal file/folder colors
- `etc/dnyf/icons/` — icon registry
- `etc/dnyf/archive/` — ZIP/archive appearance
- `config/theme/` — user-facing theme configuration
- `config/colors/` — color configuration
- `config/icons/` — icon configuration
- `usr/share/dnyf/theme/` — shared runtime theme
- `usr/share/dnyf/icons/` — shared runtime icons

Brand:

DNYFTECH

Platform:

DNYF OS

Development environment:

DNYF-DEV

AI platform:

CEEZIX

Primary terminal identity:

Cyan / Blue / Green with Yellow warnings and Red errors.

Fonts:

JetBrains Mono for technical interfaces.
Syne for visual/UI headings.
DOC

###############################################################################
# 10. FINAL VALIDATION
###############################################################################

printf "\n"
printf "${CYAN}Applying DNYF visual system...${RESET}\n"

if command -v dircolors >/dev/null 2>&1; then
    printf "${GREEN}[OK]${RESET} dircolors available\n"
else
    printf "${YELLOW}[INFO]${RESET} dircolors not installed; metadata retained\n"
fi

if command -v node >/dev/null 2>&1; then
    printf "${GREEN}[OK]${RESET} Node.js available\n"
else
    printf "${YELLOW}[INFO]${RESET} Node.js not currently available\n"
fi

printf "\n"
bash "$ROOT/scripts/validate.sh"

printf "\n${CYAN}============================================================${RESET}\n"
printf "${GREEN} DNYF-DEV FOUNDATION REPAIR COMPLETE${RESET}\n"
printf "${CYAN}============================================================${RESET}\n"

printf "\nVisual system:\n"
printf "  ${CYAN}◆${RESET} DNYFTECH\n"
printf "  ${CYAN}◈${RESET} DNYF-DEV\n"
printf "  ${CYAN}▰${RESET} folders\n"
printf "  ${WHITE}▱${RESET} files\n"
printf "  ${GREEN}▶${RESET} executables\n"
printf "  ${RED}▤${RESET} ZIP/archives\n"
printf "  ${MAGENTA}✦${RESET} AI/engines\n"
printf "  ${YELLOW}⚙${RESET} configuration\n"
printf "  ${GREEN}✓${RESET} success\n"
printf "  ${RED}✗${RESET} error\n"
printf "\n"

