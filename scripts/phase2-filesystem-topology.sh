#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_HOME="${HOME}"

C='\033[1;36m'
B='\033[1;34m'
G='\033[1;32m'
Y='\033[1;33m'
R='\033[1;31m'
M='\033[1;35m'
X='\033[0m'

printf "${C}============================================================${X}\n"
printf "${C} DNYF-DEV PHASE 2 — FILESYSTEM TOPOLOGY HARDENING${X}\n"
printf "${C}============================================================${X}\n\n"

###############################################################################
# 1. CANONICAL ROOTS
###############################################################################

printf "${C}◆ Creating canonical filesystem topology...${X}\n"

mkdir -p \
  "$ROOT" \
  "$ROOT/apps" \
  "$ROOT/backups" \
  "$ROOT/bin" \
  "$ROOT/config" \
  "$ROOT/docs" \
  "$ROOT/engines" \
  "$ROOT/home" \
  "$ROOT/logs" \
  "$ROOT/packages" \
  "$ROOT/registry" \
  "$ROOT/scripts" \
  "$ROOT/system" \
  "$ROOT/tooling" \
  "$ROOT/var" \
  "$ROOT/workspace"

###############################################################################
# 2. DNYF OS FHS-LIKE TREE
###############################################################################

mkdir -p \
  "$ROOT/boot" \
  "$ROOT/dev" \
  "$ROOT/etc" \
  "$ROOT/lib" \
  "$ROOT/lib64" \
  "$ROOT/media" \
  "$ROOT/mnt" \
  "$ROOT/opt" \
  "$ROOT/proc" \
  "$ROOT/root" \
  "$ROOT/run" \
  "$ROOT/sbin" \
  "$ROOT/srv" \
  "$ROOT/sys" \
  "$ROOT/tmp" \
  "$ROOT/usr" \
  "$ROOT/var"

mkdir -p \
  "$ROOT/usr/bin" \
  "$ROOT/usr/include" \
  "$ROOT/usr/lib" \
  "$ROOT/usr/sbin" \
  "$ROOT/usr/share" \
  "$ROOT/usr/local/bin" \
  "$ROOT/usr/local/include" \
  "$ROOT/usr/local/lib" \
  "$ROOT/usr/local/share"

mkdir -p \
  "$ROOT/var/cache" \
  "$ROOT/var/lib" \
  "$ROOT/var/local" \
  "$ROOT/var/lock" \
  "$ROOT/var/log" \
  "$ROOT/var/mail" \
  "$ROOT/var/opt" \
  "$ROOT/var/run" \
  "$ROOT/var/spool" \
  "$ROOT/var/tmp"

###############################################################################
# 3. DNYF NAMESPACE
###############################################################################

mkdir -p \
  "$ROOT/opt/dnyf" \
  "$ROOT/opt/dnyf/apps" \
  "$ROOT/opt/dnyf/bin" \
  "$ROOT/opt/dnyf/config" \
  "$ROOT/opt/dnyf/engines" \
  "$ROOT/opt/dnyf/models" \
  "$ROOT/opt/dnyf/packages" \
  "$ROOT/opt/dnyf/plugins" \
  "$ROOT/opt/dnyf/runtime" \
  "$ROOT/opt/dnyf/state" \
  "$ROOT/opt/dnyf/workspace" \
  "$ROOT/opt/dnyf/tools" \
  "$ROOT/opt/dnyf/compat"

###############################################################################
# 4. RUNTIME LAYERS
###############################################################################

mkdir -p \
  "$ROOT/opt/dnyf/runtime/device" \
  "$ROOT/opt/dnyf/runtime/discovery" \
  "$ROOT/opt/dnyf/runtime/pairing" \
  "$ROOT/opt/dnyf/runtime/secure" \
  "$ROOT/opt/dnyf/runtime/sync" \
  "$ROOT/opt/dnyf/runtime/transfer" \
  "$ROOT/opt/dnyf/runtime/trust" \
  "$ROOT/opt/dnyf/runtime/session" \
  "$ROOT/opt/dnyf/runtime/gateway" \
  "$ROOT/opt/dnyf/runtime/ceezix"

mkdir -p \
  "$ROOT/opt/dnyf/state/device" \
  "$ROOT/opt/dnyf/state/discovery" \
  "$ROOT/opt/dnyf/state/pairing" \
  "$ROOT/opt/dnyf/state/security" \
  "$ROOT/opt/dnyf/state/sync" \
  "$ROOT/opt/dnyf/state/transfer" \
  "$ROOT/opt/dnyf/state/trust" \
  "$ROOT/opt/dnyf/state/session" \
  "$ROOT/opt/dnyf/state/gateway" \
  "$ROOT/opt/dnyf/state/ceezix"

###############################################################################
# 5. CONFIGURATION LAYERS
###############################################################################

mkdir -p \
  "$ROOT/etc/dnyf" \
  "$ROOT/etc/dnyf/auth" \
  "$ROOT/etc/dnyf/pairing" \
  "$ROOT/etc/dnyf/session" \
  "$ROOT/etc/dnyf/security" \
  "$ROOT/etc/dnyf/sync" \
  "$ROOT/etc/dnyf/transfer" \
  "$ROOT/etc/dnyf/trust" \
  "$ROOT/etc/dnyf/theme" \
  "$ROOT/etc/dnyf/colors" \
  "$ROOT/etc/dnyf/icons" \
  "$ROOT/etc/dnyf/archive" \
  "$ROOT/etc/dnyf/phase" \
  "$ROOT/etc/dnyf/network" \
  "$ROOT/etc/dnyf/platform" \
  "$ROOT/etc/dnyf/registry"

###############################################################################
# 6. WORKSPACE MIRROR
###############################################################################

mkdir -p \
  "$ROOT/workspace/apps" \
  "$ROOT/workspace/engines" \
  "$ROOT/workspace/projects" \
  "$ROOT/workspace/packages" \
  "$ROOT/workspace/models" \
  "$ROOT/workspace/tools" \
  "$ROOT/workspace/docs" \
  "$ROOT/workspace/tests" \
  "$ROOT/workspace/sandbox" \
  "$ROOT/workspace/shared"

###############################################################################
# 7. HOME MIRROR
###############################################################################

mkdir -p \
  "$ROOT/home/Projects" \
  "$ROOT/home/Workspace" \
  "$ROOT/home/AI" \
  "$ROOT/home/.config" \
  "$ROOT/home/.cache" \
  "$ROOT/home/.local" \
  "$ROOT/home/.local/bin"

###############################################################################
# 8. SYSTEM / REGISTRY / TOOLING
###############################################################################

mkdir -p \
  "$ROOT/system/boot" \
  "$ROOT/system/services" \
  "$ROOT/system/drivers" \
  "$ROOT/system/security" \
  "$ROOT/system/network" \
  "$ROOT/system/runtime"

mkdir -p \
  "$ROOT/registry/devices" \
  "$ROOT/registry/services" \
  "$ROOT/registry/plugins" \
  "$ROOT/registry/packages" \
  "$ROOT/registry/capabilities"

mkdir -p \
  "$ROOT/tooling/bin" \
  "$ROOT/tooling/installers" \
  "$ROOT/tooling/validators" \
  "$ROOT/tooling/builders" \
  "$ROOT/tooling/diagnostics"

###############################################################################
# 9. SAFE SYMLINK FUNCTION
###############################################################################

link_force() {
    local target="$1"
    local link="$2"

    mkdir -p "$(dirname "$link")"

    if [ -L "$link" ] || [ -e "$link" ]; then
        rm -rf "$link"
    fi

    ln -s "$target" "$link"
}

###############################################################################
# 10. INTERNAL DNYF PATH GRAPH
#
# Canonical physical storage remains under ROOT.
# Aliases point toward canonical locations.
###############################################################################

printf "${B}◈ Installing internal DNYF path graph...${X}\n"

link_force "$ROOT/workspace" \
           "$ROOT/dev"

link_force "$ROOT/workspace/apps" \
           "$ROOT/apps-workspace"

link_force "$ROOT/var" \
           "$ROOT/runtime"

link_force "$ROOT/system" \
           "$ROOT/sys-dnyf"

link_force "$ROOT/home" \
           "$ROOT/user"

link_force "$ROOT/opt/dnyf/apps" \
           "$ROOT/dnyf-apps"

link_force "$ROOT/opt/dnyf/engines" \
           "$ROOT/dnyf-engines"

link_force "$ROOT/opt/dnyf/models" \
           "$ROOT/dnyf-models"

link_force "$ROOT/opt/dnyf/packages" \
           "$ROOT/dnyf-packages"

link_force "$ROOT/opt/dnyf/plugins" \
           "$ROOT/dnyf-plugins"

link_force "$ROOT/opt/dnyf/runtime" \
           "$ROOT/dnyf-runtime"

link_force "$ROOT/opt/dnyf/state" \
           "$ROOT/dnyf-state"

link_force "$ROOT/opt/dnyf/workspace" \
           "$ROOT/dnyf-workspace"

###############################################################################
# 11. /USR COMPATIBILITY LINKS
###############################################################################

link_force "$ROOT/bin" \
           "$ROOT/usr/local/dnyf-bin"

link_force "$ROOT/bin" \
           "$ROOT/usr/dnyf-bin"

link_force "$ROOT/scripts" \
           "$ROOT/usr/share/dnyf-scripts"

link_force "$ROOT/docs" \
           "$ROOT/usr/share/dnyf-docs"

###############################################################################
# 12. TERMUX INTEGRATION
###############################################################################

printf "${B}⌁ Installing Termux integration...${X}\n"

mkdir -p "$ROOT/compat/termux"

cat > "$ROOT/compat/termux/paths.env" <<EOF
DNYF_ROOT=$ROOT
DNYF_PREFIX=$PREFIX
DNYF_TERMUX_HOME=$TERMUX_HOME
DNYF_TERMUX_STORAGE=$TERMUX_HOME/storage
DNYF_TERMUX_SHARED=$TERMUX_HOME/storage/shared
EOF

link_force "$PREFIX" \
           "$ROOT/compat/termux/prefix"

link_force "$TERMUX_HOME" \
           "$ROOT/compat/termux/home"

###############################################################################
# 13. ANDROID LOCAL STORAGE
#
# These links are deliberately allowed to be dangling.
# termux-setup-storage may not have been executed yet.
###############################################################################

mkdir -p "$ROOT/local"

ANDROID_SHARED="$TERMUX_HOME/storage/shared"
ANDROID_DOWNLOADS="$ANDROID_SHARED/Download"
ANDROID_DCIM="$ANDROID_SHARED/DCIM"
ANDROID_DOCUMENTS="$ANDROID_SHARED/Documents"
ANDROID_PICTURES="$ANDROID_SHARED/Pictures"
ANDROID_MUSIC="$ANDROID_SHARED/Music"
ANDROID_MOVIES="$ANDROID_SHARED/Movies"
ANDROID_ANDROID="$ANDROID_SHARED/Android"

link_force "$ANDROID_SHARED" \
           "$ROOT/local/shared"

link_force "$ANDROID_DOWNLOADS" \
           "$ROOT/local/Download"

link_force "$ANDROID_DOCUMENTS" \
           "$ROOT/local/Documents"

link_force "$ANDROID_DCIM" \
           "$ROOT/local/DCIM"

link_force "$ANDROID_PICTURES" \
           "$ROOT/local/Pictures"

link_force "$ANDROID_MUSIC" \
           "$ROOT/local/Music"

link_force "$ANDROID_MOVIES" \
           "$ROOT/local/Movies"

link_force "$ANDROID_ANDROID" \
           "$ROOT/local/Android"

###############################################################################
# 14. USER-FACING STORAGE ALIASES
###############################################################################

link_force "$ROOT/local/shared" \
           "$ROOT/storage"

link_force "$ROOT/local/Download" \
           "$ROOT/downloads"

link_force "$ROOT/local/Documents" \
           "$ROOT/documents"

link_force "$ROOT/local/Pictures" \
           "$ROOT/pictures"

link_force "$ROOT/local/Music" \
           "$ROOT/music"

link_force "$ROOT/local/Movies" \
           "$ROOT/movies"

###############################################################################
# 15. DNYF DATA MIRRORS ON LOCAL STORAGE
#
# These become usable automatically once Android shared storage exists.
###############################################################################

link_force "$ROOT/local/shared/DNYF-DEV" \
           "$ROOT/local/dnyf-shared"

link_force "$ROOT/local/shared/DNYF-DEV/Projects" \
           "$ROOT/local/projects"

link_force "$ROOT/local/shared/DNYF-DEV/Workspace" \
           "$ROOT/local/workspace"

link_force "$ROOT/local/shared/DNYF-DEV/Backups" \
           "$ROOT/local/backups"

link_force "$ROOT/local/shared/DNYF-DEV/Packages" \
           "$ROOT/local/packages"

link_force "$ROOT/local/shared/DNYF-DEV/Exports" \
           "$ROOT/local/exports"

###############################################################################
# 16. UBUNTU / PROOT COMPATIBILITY
#
# Do NOT assume Ubuntu is installed.
# We create a stable DNYF compatibility namespace and dangling links.
###############################################################################

printf "${B}▣ Installing Ubuntu/proot compatibility topology...${X}\n"

mkdir -p \
  "$ROOT/compat/linux" \
  "$ROOT/compat/ubuntu" \
  "$ROOT/compat/proot"

PROOT_BASE="$PREFIX/var/lib/proot-distro"

UBUNTU_ROOT="$PROOT_BASE/installed-rootfs/ubuntu"
UBUNTU_QUESTING="$PROOT_BASE/installed-rootfs/ubuntu-questing-aarch64"
UBUNTU_QUESTING_ALT="$PROOT_BASE/installed-rootfs/ubuntu-questing"

link_force "$UBUNTU_ROOT" \
           "$ROOT/compat/ubuntu/rootfs"

link_force "$UBUNTU_QUESTING" \
           "$ROOT/compat/ubuntu/questing-aarch64"

link_force "$UBUNTU_QUESTING_ALT" \
           "$ROOT/compat/ubuntu/questing"

link_force "$PROOT_BASE" \
           "$ROOT/compat/proot/proot-distro"

###############################################################################
# 17. UBUNTU INTERNAL DNYF MOUNTS / LINKS
#
# These are paths inside the expected Ubuntu rootfs.
# They may remain dangling until Ubuntu exists.
###############################################################################

UB="$ROOT/compat/ubuntu/rootfs"

for p in \
    opt/dnyf \
    opt/dnyf/apps \
    opt/dnyf/config \
    opt/dnyf/engines \
    opt/dnyf/models \
    opt/dnyf/packages \
    opt/dnyf/plugins \
    opt/dnyf/runtime \
    opt/dnyf/state \
    opt/dnyf/tools \
    opt/dnyf/workspace \
    etc/dnyf \
    usr/local/bin \
    var/log/dnyf \
    var/lib/dnyf \
    var/cache/dnyf \
    home/DNYF \
    home/Projects \
    home/Workspace \
    home/AI
do
    mkdir -p "$ROOT/compat/ubuntu/links/$p"
done

###############################################################################
# 18. UBUNTU → DNYF HOST BRIDGES
#
# These links are intentionally created as links in the compatibility
# namespace, without modifying a non-existent Ubuntu rootfs.
###############################################################################

link_force "$ROOT" \
           "$ROOT/compat/ubuntu/links/host-dnyf"

link_force "$ROOT/workspace" \
           "$ROOT/compat/ubuntu/links/workspace"

link_force "$ROOT/opt/dnyf" \
           "$ROOT/compat/ubuntu/links/opt-dnyf"

###############################################################################
# 19. PHASE RUNTIME ALIASES
###############################################################################

for P in \
    device \
    discovery \
    pairing \
    secure \
    sync \
    transfer \
    trust \
    session \
    gateway \
    ceezix
do
    mkdir -p "$ROOT/opt/dnyf/runtime/$P"
    mkdir -p "$ROOT/opt/dnyf/state/$P"

    link_force "$ROOT/opt/dnyf/runtime/$P" \
               "$ROOT/runtime-$P"

    link_force "$ROOT/opt/dnyf/state/$P" \
               "$ROOT/state-$P"
done

###############################################################################
# 20. CEEZIX ALIASES
###############################################################################

link_force "$ROOT/opt/dnyf/runtime/ceezix" \
           "$ROOT/ceezix-runtime"

link_force "$ROOT/opt/dnyf/models" \
           "$ROOT/ceezix-models"

link_force "$ROOT/opt/dnyf/tools" \
           "$ROOT/ceezix-tools"

###############################################################################
# 21. BIN EXECUTION PATH
###############################################################################

mkdir -p "$ROOT/bin"

link_force "$ROOT/bin" \
           "$ROOT/opt/dnyf/bin-host"

link_force "$ROOT/usr/local/bin" \
           "$ROOT/opt/dnyf/bin-local"

###############################################################################
# 22. PLACEHOLDER MARKERS
###############################################################################

touch "$ROOT/dev/.dnyf-runtime-placeholder"
touch "$ROOT/proc/.dnyf-runtime-placeholder"
touch "$ROOT/sys/.dnyf-runtime-placeholder"
touch "$ROOT/run/.dnyf-runtime-placeholder"
touch "$ROOT/root/.dnyf-root-namespace"

###############################################################################
# 23. TOPOLOGY MANIFEST
###############################################################################

cat > "$ROOT/etc/dnyf/platform/topology.json" <<EOF
{
  "schema": "dnyf.filesystem.topology.v1",
  "root": "$ROOT",
  "canonical_root": "$ROOT",
  "termux_prefix": "$PREFIX",
  "termux_home": "$TERMUX_HOME",
  "android_shared": "$ANDROID_SHARED",
  "ubuntu_proot_base": "$PROOT_BASE",
  "ubuntu_root": "$UBUNTU_ROOT",
  "policy": {
    "canonical_storage": "DNYF-DEV",
    "allow_dangling_compatibility_links": true,
    "allow_missing_ubuntu_links": true,
    "allow_missing_android_storage_links": true,
    "prevent_recursive_self_links": true,
    "preserve_canonical_paths": true
  },
  "aliases": {
    "dev": "workspace",
    "runtime": "var",
    "user": "home",
    "apps-workspace": "workspace/apps",
    "dnyf-apps": "opt/dnyf/apps",
    "dnyf-engines": "opt/dnyf/engines",
    "dnyf-models": "opt/dnyf/models",
    "dnyf-packages": "opt/dnyf/packages",
    "dnyf-runtime": "opt/dnyf/runtime",
    "dnyf-state": "opt/dnyf/state",
    "dnyf-workspace": "opt/dnyf/workspace"
  }
}
EOF

###############################################################################
# 24. TOPOLOGY VALIDATOR
###############################################################################

cat > "$ROOT/scripts/validate-topology.sh" <<'EOF'
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
EOF

chmod +x "$ROOT/scripts/validate-topology.sh"

###############################################################################
# 25. DNYF TOPOLOGY COMMAND
###############################################################################

cat > "$ROOT/bin/dnyf-topology" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

case "${1:-show}" in

show)
    printf '\033[1;36m◆ DNYFTECH FILESYSTEM TOPOLOGY\033[0m\n'
    printf '\033[1;36m◈ Root:\033[0m %s\n' "$ROOT"
    printf '\033[1;36m▣ Ubuntu:\033[0m %s\n' "$ROOT/compat/ubuntu/rootfs"
    printf '\033[1;36m⌁ Android:\033[0m %s\n' "$ROOT/local/shared"
    printf '\033[1;36m▤ Workspace:\033[0m %s\n' "$ROOT/workspace"
    printf '\033[1;36m⚙ Runtime:\033[0m %s\n' "$ROOT/opt/dnyf/runtime"
    printf '\033[1;36m⛨ Security:\033[0m %s\n' "$ROOT/etc/dnyf/security"
    printf '\033[1;36m✦ CEEZIX:\033[0m %s\n' "$ROOT/opt/dnyf/runtime/ceezix"
    ;;

links)
    find "$ROOT" -type l -printf '%p -> %l\n' 2>/dev/null
    ;;

dangling)
    find "$ROOT" -type l ! -exec test -e {} \; -printf '%p -> %l\n' 2>/dev/null
    ;;

validate)
    exec "$ROOT/scripts/validate-topology.sh"
    ;;

*)
    printf 'Usage: dnyf-topology {show|links|dangling|validate}\n'
    exit 1
    ;;

esac
EOF

chmod +x "$ROOT/bin/dnyf-topology"

ln -sf "$ROOT/bin/dnyf-topology" "$ROOT/usr/local/bin/dnyf-topology"
ln -sf "$ROOT/bin/dnyf-topology" "$ROOT/usr/bin/dnyf-topology"

###############################################################################
# 26. FINAL VALIDATION
###############################################################################

printf "\n${C}============================================================${X}\n"
printf "${C} TOPOLOGY VALIDATION${X}\n"
printf "${C}============================================================${X}\n\n"

"$ROOT/scripts/validate-topology.sh"

printf "\n"
printf "${G}◆ DNYFTECH${X}\n"
printf "${C}◈ DNYF-DEV filesystem topology installed.${X}\n"
printf "${M}✦ CEEZIX compatibility namespace ready.${X}\n"
printf "${B}▣ Ubuntu/proot compatibility links established.${X}\n"
printf "${C}⌁ Android/local-storage links established.${X}\n"
printf "\n"
printf "Inspect: ${C}dnyf-topology show${X}\n"
printf "Links:   ${C}dnyf-topology links${X}\n"
printf "Broken:  ${C}dnyf-topology dangling${X}\n"
printf "Test:    ${C}dnyf-topology validate${X}\n"
printf "\n"

exit 0
