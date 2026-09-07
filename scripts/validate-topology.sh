#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

G='\033[1;32m'
R='\033[1;31m'
C='\033[1;36m'
X='\033[0m'

PASS=0
FAIL=0

ok() {
    printf "${G}[OK]${X}   %s\n" "$1"
    PASS=$((PASS+1))
}

fail() {
    printf "${R}[FAIL]${X} %s\n" "$1"
    FAIL=$((FAIL+1))
}

check_link() {
    local link="$1"
    if [ -L "$link" ]; then
        ok "symlink: ${link#$ROOT/}"
    else
        fail "missing symlink: ${link#$ROOT/}"
    fi
}

printf "${C}============================================================${X}\n"
printf "${C} DNYF-DEV FILESYSTEM TOPOLOGY VALIDATION${X}\n"
printf "${C}============================================================${X}\n"

[ -d "$ROOT" ] && ok "canonical root" || fail "canonical root"

for d in \
    apps backups bin config docs engines home logs packages registry \
    scripts system tooling var workspace opt etc usr local
do
    [ -d "$ROOT/$d" ] && ok "directory: $d" || fail "directory: $d"
done

for l in \
    "$ROOT/dev" \
    "$ROOT/apps-workspace" \
    "$ROOT/runtime" \
    "$ROOT/user" \
    "$ROOT/dnyf-apps" \
    "$ROOT/dnyf-engines" \
    "$ROOT/dnyf-models" \
    "$ROOT/dnyf-packages" \
    "$ROOT/dnyf-runtime" \
    "$ROOT/dnyf-state" \
    "$ROOT/dnyf-workspace" \
    "$ROOT/storage" \
    "$ROOT/downloads" \
    "$ROOT/documents" \
    "$ROOT/pictures" \
    "$ROOT/music" \
    "$ROOT/movies" \
    "$ROOT/compat/termux/prefix" \
    "$ROOT/compat/termux/home" \
    "$ROOT/compat/ubuntu/rootfs" \
    "$ROOT/compat/proot/proot-distro"
do
    check_link "$l"
done

###############################################################################
# Recursive self-link detection
###############################################################################

SELF_LINK="$ROOT/DNYF-DEV"

if [ -L "$SELF_LINK" ]; then
    fail "recursive/self DNYF-DEV link detected"
else
    ok "no recursive DNYF-DEV self-link"
fi

###############################################################################
# Canonical device ID
###############################################################################

ID_FILE="$ROOT/etc/dnyf/device-id"

if [ -f "$ID_FILE" ] &&
   grep -Eq '^[[:xdigit:]]{32}$' "$ID_FILE"
then
    ok "canonical device ID"
else
    fail "canonical device ID"
fi

###############################################################################
# Dangling links are informational, not failures.
###############################################################################

DANGLING="$(find "$ROOT" -type l ! -exec test -e {} \; 2>/dev/null | wc -l | tr -d ' ')"

printf "${C}[INFO]${X} dangling compatibility links: $DANGLING\n"

printf "\n"
printf "${C}Topology validation: ${G}$PASS passed${X}, ${R}$FAIL failed${X}\n"

if [ "$FAIL" -eq 0 ]; then
    printf "${G}FILESYSTEM TOPOLOGY: PASS${X}\n"
    exit 0
fi

printf "${R}FILESYSTEM TOPOLOGY: FAIL${X}\n"
exit 1
