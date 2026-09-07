#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

C='\033[1;36m'
G='\033[1;32m'
R='\033[1;31m'
Y='\033[1;33m'
W='\033[1;37m'
M='\033[1;35m'
X='\033[0m'

FAILED=0

ok() {
    printf "${G}[OK]${X}   %s\n" "$1"
}

fail() {
    printf "${R}[FAIL]${X} %s\n" "$1"
    FAILED=1
}

printf "\n"
printf "${C}============================================================${X}\n"
printf "${C} DNYF-DEV FILESYSTEM VALIDATION${X}\n"
printf "${C}============================================================${X}\n"

[ -f "$ROOT/etc/os-release" ] && ok "DNYF OS identity" || fail "DNYF OS identity"

DEVICE_ID="$(cat "$ROOT/etc/dnyf/device-id" 2>/dev/null || true)"

[ "$DEVICE_ID" = "cbd06be57a51cb84e12b4e112a4d06e9" ] \
&& ok "canonical device ID" \
|| fail "canonical device ID"

[ -f "$ROOT/etc/dnyf/identity.json" ] && ok "identity metadata" || fail "identity metadata"
[ -f "$ROOT/etc/dnyf/platform.json" ] && ok "platform metadata" || fail "platform metadata"
[ -f "$ROOT/etc/dnyf/capabilities.json" ] && ok "capability registry" || fail "capability registry"
[ -f "$ROOT/etc/dnyf/security-policy.json" ] && ok "security policy" || fail "security policy"
[ -f "$ROOT/etc/dnyf/auth/protocol.json" ] && ok "cryptographic auth protocol" || fail "cryptographic auth protocol"
[ -f "$ROOT/etc/dnyf/pairing/config.json" ] && ok "pairing configuration" || fail "pairing configuration"
[ -f "$ROOT/etc/dnyf/pairing/session-protocol.json" ] && ok "session protocol" || fail "session protocol"
[ -f "$ROOT/etc/dnyf/sync/config.json" ] && ok "sync configuration" || fail "sync configuration"
[ -f "$ROOT/etc/dnyf/trust/peers.json" ] && ok "trust registry" || fail "trust registry"
[ -f "$ROOT/registry/services.json" ] && ok "service registry" || fail "service registry"
[ -f "$ROOT/etc/dnyf/phase-manifest.json" ] && ok "phase manifest" || fail "phase manifest"
[ -f "$ROOT/etc/dnyf/transfer/protocol.json" ] && ok "transfer protocol" || fail "transfer protocol"
[ -x "$ROOT/bin/dnyf" ] && ok "DNYF CLI" || fail "DNYF CLI"

###############################################################################
# TRUST POLICY — NO PYTHON
###############################################################################

TRUST="$ROOT/etc/dnyf/trust/peers.json"

if [ -f "$TRUST" ]; then

    LOCAL_ID="$(sed -n \
      's/.*"local_device_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$TRUST" | head -n1)"

    SELF_TRUST="$(sed -n \
      's/.*"self_trust"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' \
      "$TRUST" | head -n1)"

    if [ "$LOCAL_ID" = "$DEVICE_ID" ] &&
       [ "$SELF_TRUST" = "false" ] &&
       grep -q '"peers"[[:space:]]*:[[:space:]]*\[[[:space:]]*\]' "$TRUST"
    then
        ok "trust registry policy"
    else
        fail "trust registry policy"
    fi

else
    fail "trust registry policy"
fi

###############################################################################
# VISUAL SYSTEM
###############################################################################

[ -f "$ROOT/etc/dnyf/theme/theme.json" ] \
&& ok "DNYF visual theme" \
|| fail "DNYF visual theme"

[ -f "$ROOT/etc/dnyf/colors/dircolors" ] \
&& ok "directory/file colors" \
|| fail "directory/file colors"

[ -f "$ROOT/etc/dnyf/icons/icons.json" ] \
&& ok "icon registry" \
|| fail "icon registry"

[ -f "$ROOT/etc/dnyf/archive/archive-theme.json" ] \
&& ok "archive/ZIP visual metadata" \
|| fail "archive/ZIP visual metadata"

###############################################################################
# STRUCTURE
###############################################################################

for D in \
apps backups bin config docs engines home logs packages registry scripts \
system tooling var workspace opt/dnyf etc/dnyf usr/local/bin
do
    [ -d "$ROOT/$D" ] && ok "directory: $D" || fail "directory: $D"
done

###############################################################################
# SECURITY
###############################################################################

grep -q '"self_trust"[[:space:]]*:[[:space:]]*false' "$TRUST" \
&& ok "self-trust disabled" \
|| fail "self-trust disabled"

grep -q '"automatic_trust"[[:space:]]*:[[:space:]]*false' \
"$ROOT/etc/dnyf/pairing/config.json" \
&& ok "automatic trust disabled" \
|| fail "automatic trust disabled"

grep -q '"self_pairing"[[:space:]]*:[[:space:]]*false' \
"$ROOT/etc/dnyf/pairing/config.json" \
&& ok "self-pairing disabled" \
|| fail "self-pairing disabled"

printf "\n"
printf "${C}============================================================${X}\n"

if [ "$FAILED" -eq 0 ]; then
    printf "${G} VALIDATION: PASS${X}\n"
else
    printf "${R} VALIDATION: FAIL${X}\n"
fi

printf "${C}============================================================${X}\n"

exit "$FAILED"
