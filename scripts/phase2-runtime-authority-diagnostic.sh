#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="$HOME/DNYF-DEV"
export DNYF_ROOT="$ROOT"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

echo "============================================================"
echo " DNYF-DEV — PHASE 2 RUNTIME AUTHORITY DIAGNOSTIC"
echo "============================================================"
echo

echo "◆ 1. Canonical device identity"
echo "------------------------------------------------------------"

for f in \
  "$ROOT/etc/dnyf/identity.json" \
  "$ROOT/opt/dnyf/runtime/secure/identity/identity.json" \
  "$ROOT/etc/dnyf/device-id" \
  "$ROOT/etc/dnyf/device-identity.json"
do
    if [ -f "$f" ]; then
        echo "[FOUND] $f"
        sed -n '1,120p' "$f"
        echo
    else
        echo "[MISS ] $f"
    fi
done

echo
echo "◆ 2. Search ALL existing cryptographic identity material"
echo "------------------------------------------------------------"

find "$ROOT" \
    -type f \
    \( \
      -name 'identity.json' -o \
      -name '*identity*.json' -o \
      -name '*ed25519*' -o \
      -name '*public*.pem' -o \
      -name '*private*.pem' \
    \) \
    ! -path '*/node_modules/*' \
    ! -path '*/.git/*' \
    -print 2>/dev/null | sort

echo
echo "◆ 3. Search for canonical device ID references"
echo "------------------------------------------------------------"

grep -RIl \
    'cbd06be57a51cb84e12b4e112a4d06e9' \
    "$ROOT/etc" \
    "$ROOT/opt/dnyf" \
    "$ROOT/registry" \
    "$ROOT/config" \
    "$ROOT/system" \
    2>/dev/null | sort | head -200

echo
echo "◆ 4. Universal runtime files"
echo "------------------------------------------------------------"

find "$ROOT/opt/dnyf/runtime/universal" \
    -maxdepth 2 \
    -type f \
    -print 2>/dev/null | sort

echo
echo "◆ 5. Runtime core module exports"
echo "------------------------------------------------------------"

node - <<'NODE'
const path = require('path');

const root = process.env.DNYF_ROOT;
const file = path.join(
    root,
    'opt/dnyf/runtime/universal/dnyf-runtime-core.js'
);

console.log('CORE:', file);

try {
    const core = require(file);

    console.log('\nTYPE:', typeof core);

    if (core && typeof core === 'object') {
        console.log('\nEXPORTS:');
        console.log(Object.keys(core).sort());

        console.log('\nDESCRIPTORS:');
        for (const key of Object.keys(core).sort()) {
            const value = core[key];
            console.log(
                `${key}: ${typeof value}`
            );
        }
    } else {
        console.log('\nVALUE:');
        console.dir(core, {depth: 4});
    }
} catch (error) {
    console.error('\nCORE LOAD ERROR');
    console.error(error.stack || error);
    process.exitCode = 1;
}
NODE

echo
echo "◆ 6. Runtime identity module exports"
echo "------------------------------------------------------------"

node - <<'NODE'
const path = require('path');

const root = process.env.DNYF_ROOT;
const file = path.join(
    root,
    'opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js'
);

console.log('IDENTITY:', file);

try {
    const identity = require(file);

    console.log('\nTYPE:', typeof identity);

    if (identity && typeof identity === 'object') {
        console.log('\nEXPORTS:');
        console.log(Object.keys(identity).sort());
    }

    console.log('\nMODULE:');
    console.dir(identity, {depth: 5});
} catch (error) {
    console.error('\nIDENTITY LOAD ERROR');
    console.error(error.stack || error);
    process.exitCode = 1;
}
NODE

echo
echo "◆ 7. Runtime protocol + manifest"
echo "------------------------------------------------------------"

for f in \
  "$ROOT/etc/dnyf/runtime/dnyf-runtime-protocol.json" \
  "$ROOT/etc/dnyf/runtime/dnyf-runtime-manifest.json" \
  "$ROOT/etc/dnyf/runtime/dnyf-runtime-identity-authority.json"
do
    if [ -f "$f" ]; then
        echo
        echo "===== $f ====="
        cat "$f"
    else
        echo "[MISSING] $f"
    fi
done

echo
echo "◆ 8. Validator locations"
echo "------------------------------------------------------------"

find "$ROOT/opt/dnyf/runtime" \
    -name 'dnyf-runtime-validator.sh' \
    -print 2>/dev/null

echo
echo "◆ 9. Security-material summary"
echo "------------------------------------------------------------"

PRIVATE_COUNT="$(find "$ROOT" -type f \
    \( -name '*private*.pem' -o -name '*private*.key' \) \
    ! -path '*/node_modules/*' \
    ! -path '*/.git/*' \
    2>/dev/null | wc -l)"

PUBLIC_COUNT="$(find "$ROOT" -type f \
    \( -name '*public*.pem' -o -name '*public*.key' \) \
    ! -path '*/node_modules/*' \
    ! -path '*/.git/*' \
    2>/dev/null | wc -l)"

IDENTITY_COUNT="$(find "$ROOT" -type f \
    \( -name 'identity.json' -o -name '*identity*.json' \) \
    ! -path '*/node_modules/*' \
    ! -path '*/.git/*' \
    2>/dev/null | wc -l)"

echo "identity JSON files : $IDENTITY_COUNT"
echo "private key files   : $PRIVATE_COUNT"
echo "public key files    : $PUBLIC_COUNT"

echo
echo "============================================================"
echo " DIAGNOSTIC COMPLETE"
echo "============================================================"
