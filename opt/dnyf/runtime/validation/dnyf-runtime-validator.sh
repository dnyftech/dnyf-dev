#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

CYAN=$'\033[1;36m'
GREEN=$'\033[1;32m'
RED=$'\033[1;31m'
RESET=$'\033[0m'

PASS=0
FAIL=0

check_file() {
    local label="$1"
    local file="$2"

    if [ -f "$file" ]; then
        printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$label"
        PASS=$((PASS + 1))
    else
        printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$label"
        FAIL=$((FAIL + 1))
    fi
}

check_file \
    "platform detector" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js"

check_file \
    "identity loader" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js"

check_file \
    "capability detector" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js"

check_file \
    "artifact manager" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js"

check_file \
    "dispatcher" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js"

check_file \
    "runtime core" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"

check_file \
    "Windows artifact adapter" \
    "$ROOT/opt/dnyf/runtime/windows/dnyf-runtime-windows-artifact-adapter.js"

check_file \
    "runtime protocol" \
    "$ROOT/etc/dnyf/runtime/dnyf-runtime-protocol.json"

check_file \
    "runtime manifest" \
    "$ROOT/etc/dnyf/runtime/dnyf-runtime-manifest.json"

check_file \
    "runtime registry" \
    "$ROOT/registry/dnyf-runtime-components.json"

check_file \
    "runtime CLI" \
    "$ROOT/bin/dnyf-runtime"

check_file \
    "platform metadata" \
    "$ROOT/etc/dnyf/platform/dnyf-runtime-platform.json"

check_file \
    "capability metadata" \
    "$ROOT/etc/dnyf/capabilities/dnyf-runtime-capabilities.json"

printf '\n'

export DNYF_ROOT="$ROOT"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"

node --check \
    "$ROOT/opt/dnyf/runtime/windows/dnyf-runtime-windows-artifact-adapter.js"

printf '%b[OK]%b JavaScript syntax validation\n' "$GREEN" "$RESET"

INFO="$(node "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js")"

printf '%s\n' "$INFO" | grep -q '"runtime": "dnyf-universal-runtime/1"'
printf '%b[OK]%b runtime protocol identity\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"remote_execution": false'
printf '%b[OK]%b remote execution disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"remote_installation": false'
printf '%b[OK]%b remote installation disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"remote_shell": false'
printf '%b[OK]%b remote shell disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"self_trust": false'
printf '%b[OK]%b self-trust disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"self_pairing": false'
printf '%b[OK]%b self-pairing disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"automatic_trust": false'
printf '%b[OK]%b automatic trust disabled\n' "$GREEN" "$RESET"

printf '\n'
printf '%bRuntime validation: %s passed, %s failed%b\n' \
    "$CYAN" "$PASS" "$FAIL" "$RESET"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

printf '%bUNIVERSAL RUNTIME: PASS%b\n' "$GREEN" "$RESET"
