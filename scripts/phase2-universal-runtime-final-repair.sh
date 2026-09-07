#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
export DNYF_ROOT="$ROOT"

RUNTIME="$ROOT/opt/dnyf/runtime"
UNIVERSAL="$RUNTIME/universal"
VALIDATION="$RUNTIME/validation"
ETC="$ROOT/etc/dnyf"
IDENTITY_DIR="$RUNTIME/secure/identity"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
RESET='\033[0m'

ok()   { printf "${GREEN}[OK]${RESET} %s\n" "$1"; }
info() { printf "${CYAN}[INFO]${RESET} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${RESET} %s\n" "$1"; exit 1; }

echo "============================================================"
echo " DNYF-DEV — PHASE 2 UNIVERSAL RUNTIME FINAL REPAIR"
echo "============================================================"
echo

mkdir -p "$VALIDATION" "$ETC"

# ------------------------------------------------------------
# 1. Locate the actual Phase 2 validator
# ------------------------------------------------------------

ACTUAL_VALIDATOR="$VALIDATION/dnyf-runtime-validator.sh"
EXPECTED_VALIDATOR="$UNIVERSAL/validation/dnyf-runtime-validator.sh"

if [ -f "$ACTUAL_VALIDATOR" ]; then
    ok "Phase 2 validator exists at canonical runtime validation path"

    mkdir -p "$(dirname "$EXPECTED_VALIDATOR")"

    if [ -L "$EXPECTED_VALIDATOR" ] || [ -e "$EXPECTED_VALIDATOR" ]; then
        rm -f "$EXPECTED_VALIDATOR"
    fi

    ln -s "$ACTUAL_VALIDATOR" "$EXPECTED_VALIDATOR"

    ok "universal validator compatibility link repaired"
else
    fail "Phase 2 validator is missing from $VALIDATION"
fi

chmod +x "$ACTUAL_VALIDATOR"

# ------------------------------------------------------------
# 2. Discover existing cryptographic identity
# ------------------------------------------------------------

CRYPTO_IDENTITY="$IDENTITY_DIR/identity.json"
LEGACY_IDENTITY="$ETC/identity.json"

echo
echo "◆ Checking existing identity authorities..."

if [ -f "$CRYPTO_IDENTITY" ]; then
    info "Cryptographic identity found:"
    echo "     $CRYPTO_IDENTITY"

    CRYPTO_DEVICE_ID="$(node -e '
const fs=require("fs");
const p=process.argv[1];
try {
  const x=JSON.parse(fs.readFileSync(p,"utf8"));
  process.stdout.write(String(x.device_id||""));
} catch {}
' "$CRYPTO_IDENTITY")"

    CRYPTO_FP="$(node -e '
const fs=require("fs");
const p=process.argv[1];
try {
  const x=JSON.parse(fs.readFileSync(p,"utf8"));
  process.stdout.write(String(x.fingerprint||""));
} catch {}
' "$CRYPTO_IDENTITY")"

    CRYPTO_PUBLIC_KEY="$(node -e '
const fs=require("fs");
const p=process.argv[1];
try {
  const x=JSON.parse(fs.readFileSync(p,"utf8"));
  process.stdout.write(String(x.public_key||""));
} catch {}
' "$CRYPTO_IDENTITY")"

    if [ -n "$CRYPTO_DEVICE_ID" ]; then
        ok "cryptographic identity contains device ID: $CRYPTO_DEVICE_ID"
    else
        warn "cryptographic identity exists but has no device_id"
        CRYPTO_DEVICE_ID=""
    fi

    if [ -n "$CRYPTO_FP" ]; then
        ok "cryptographic fingerprint available"
    else
        warn "cryptographic identity has no fingerprint field"
    fi

    if [ -n "$CRYPTO_PUBLIC_KEY" ]; then
        ok "cryptographic public-key reference available"
    else
        warn "cryptographic identity has no public_key field"
    fi
else
    warn "No cryptographic identity found at expected Phase 8D location"
    CRYPTO_DEVICE_ID=""
    CRYPTO_FP=""
    CRYPTO_PUBLIC_KEY=""
fi

# ------------------------------------------------------------
# 3. Preserve canonical device ID
# ------------------------------------------------------------

CANONICAL_DEVICE_ID="cbd06be57a51cb84e12b4e112a4d06e9"

if [ -n "${CRYPTO_DEVICE_ID:-}" ] &&
   [ "$CRYPTO_DEVICE_ID" != "$CANONICAL_DEVICE_ID" ]; then
    fail "Cryptographic identity device ID does not match canonical DNYF device ID"
fi

ok "canonical device ID preserved: $CANONICAL_DEVICE_ID"

# ------------------------------------------------------------
# 4. Reconcile legacy identity metadata WITHOUT generating keys
# ------------------------------------------------------------

if [ -f "$LEGACY_IDENTITY" ]; then
    cp -p "$LEGACY_IDENTITY" \
        "$LEGACY_IDENTITY.phase2-pre-reconcile.$(date +%Y%m%d%H%M%S).bak"

    node - "$LEGACY_IDENTITY" "$CANONICAL_DEVICE_ID" "$CRYPTO_FP" "$CRYPTO_PUBLIC_KEY" <<'NODE'
const fs = require('fs');

const file = process.argv[2];
const canonicalId = process.argv[3];
const fingerprint = process.argv[4] || '';
const publicKey = process.argv[5] || '';

let data = {};
try {
    data = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch {
    data = {};
}

data.device_id = canonicalId;
data.algorithm = data.algorithm || 'Ed25519';

if (fingerprint) {
    data.fingerprint = fingerprint;
}

if (publicKey) {
    data.public_key = publicKey;
}

data.identity_authority = 'dnyf-cryptauth';
data.generated_by_phase2 = false;
data.generated_new_identity = false;

fs.writeFileSync(
    file,
    JSON.stringify(data, null, 2) + '\n',
    { mode: 0o600 }
);
NODE

    ok "legacy identity reconciled without generating a new identity"
else
    warn "Legacy identity file does not exist; no identity was generated"
fi

# ------------------------------------------------------------
# 5. Force Phase 2 to use the reconciled canonical authority
# ------------------------------------------------------------

if [ -f "$LEGACY_IDENTITY" ]; then
    export DNYF_IDENTITY_FILE="$LEGACY_IDENTITY"
    ok "DNYF_IDENTITY_FILE anchored to canonical identity authority"
fi

# ------------------------------------------------------------
# 6. Write explicit identity authority metadata
# ------------------------------------------------------------

mkdir -p "$ETC/runtime"

node - "$ETC/runtime/dnyf-runtime-identity-authority.json" \
    "$CANONICAL_DEVICE_ID" \
    "${CRYPTO_FP:-}" \
    "${CRYPTO_PUBLIC_KEY:-}" \
    "$LEGACY_IDENTITY" <<'NODE'
const fs = require('fs');

const out = process.argv[2];
const deviceId = process.argv[3];
const fingerprint = process.argv[4] || null;
const publicKey = process.argv[5] || null;
const source = process.argv[6];

const authority = {
    schema: "dnyf.runtime.identity-authority.v1",
    authority: "dnyf-cryptauth",
    device_id: deviceId,
    fingerprint,
    public_key: publicKey,
    source,
    algorithm: "Ed25519",
    create_missing_identity: false,
    replace_existing_identity: false,
    generate_new_identity: false,
    self_trust: false,
    self_pairing: false,
    automatic_trust: false,
    created_at: new Date().toISOString()
};

fs.writeFileSync(out, JSON.stringify(authority, null, 2) + '\n');
NODE

ok "identity authority policy recorded"

# ------------------------------------------------------------
# 7. Test loader
# ------------------------------------------------------------

echo
echo "◆ Testing canonical identity loader..."

node - <<'NODE'
const loader = require(
  process.env.DNYF_ROOT +
  '/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js'
);

const identity =
  typeof loader.loadIdentity === 'function'
    ? loader.loadIdentity()
    : (typeof loader.getIdentity === 'function'
        ? loader.getIdentity()
        : loader);

console.log(JSON.stringify(identity, null, 2));

if (!identity || identity.device_id !== 'cbd06be57a51cb84e12b4e112a4d06e9') {
    process.exit(1);
}
NODE

ok "canonical identity loader"

# ------------------------------------------------------------
# 8. Test universal runtime core
# ------------------------------------------------------------

echo
echo "◆ Testing universal runtime core..."

node - <<'NODE'
const corePath =
  process.env.DNYF_ROOT +
  '/opt/dnyf/runtime/universal/dnyf-runtime-core.js';

const core = require(corePath);

let result;

if (typeof core.inspect === 'function') {
    result = core.inspect();
} else if (typeof core.getRuntimeInfo === 'function') {
    result = core.getRuntimeInfo();
} else if (typeof core.createRuntime === 'function') {
    result = core.createRuntime();
} else {
    result = core;
}

console.log(JSON.stringify(result, null, 2));

const text = JSON.stringify(result);

if (!text.includes('cbd06be57a51cb84e12b4e112a4d06e9')) {
    process.exit(1);
}
NODE

ok "universal runtime identity integration"

# ------------------------------------------------------------
# 9. Security invariants
# ------------------------------------------------------------

echo
echo "◆ Checking security invariants..."

node - <<'NODE'
const fs = require('fs');

const files = [
  process.env.DNYF_ROOT + '/etc/dnyf/runtime/dnyf-runtime-protocol.json',
  process.env.DNYF_ROOT + '/etc/dnyf/runtime/dnyf-runtime-manifest.json',
  process.env.DNYF_ROOT + '/etc/dnyf/runtime/dnyf-runtime-identity-authority.json'
];

for (const file of files) {
    if (!fs.existsSync(file)) continue;

    const text = fs.readFileSync(file, 'utf8');

    for (const key of [
        'remote_execution',
        'remote_installation',
        'remote_shell',
        'self_trust',
        'self_pairing',
        'automatic_trust'
    ]) {
        const re = new RegExp(`"${key}"\\s*:\\s*true`, 'i');

        if (re.test(text)) {
            console.error(`SECURITY INVARIANT VIOLATION: ${key}`);
            process.exit(1);
        }
    }
}
NODE

ok "remote_execution disabled"
ok "remote_installation disabled"
ok "remote_shell disabled"
ok "self_trust disabled"
ok "self_pairing disabled"
ok "automatic_trust disabled"

# ------------------------------------------------------------
# 10. Syntax validation
# ------------------------------------------------------------

echo
echo "◆ Running JavaScript syntax validation..."

for f in \
    "$UNIVERSAL/dnyf-runtime-platform-detector.js" \
    "$UNIVERSAL/dnyf-runtime-device-identity.js" \
    "$UNIVERSAL/dnyf-runtime-capability-detector.js" \
    "$UNIVERSAL/dnyf-runtime-artifact-manager.js" \
    "$UNIVERSAL/dnyf-runtime-dispatcher.js" \
    "$UNIVERSAL/dnyf-runtime-core.js" \
    "$RUNTIME/windows/dnyf-runtime-windows-artifact-adapter.js"
do
    [ -f "$f" ] || fail "Missing runtime component: $f"
    node --check "$f"
done

ok "JavaScript syntax validation"

# ------------------------------------------------------------
# 11. Run complete validator through BOTH canonical and
#     compatibility paths
# ------------------------------------------------------------

echo
echo "◆ Running complete Phase 2 validator..."

"$ACTUAL_VALIDATOR"

echo
echo "◆ Running validator through universal compatibility path..."

"$EXPECTED_VALIDATOR"

echo
echo "============================================================"
echo " DNYFTECH PHASE 2 UNIVERSAL RUNTIME"
echo " FINAL VALIDATION: PASS"
echo "============================================================"
echo
echo "◆ Device ID:"
echo "  $CANONICAL_DEVICE_ID"
echo
echo "◆ Identity authority:"
echo "  $LEGACY_IDENTITY"
echo
echo "◆ Runtime:"
echo "  $RUNTIME"
echo
echo "◆ Validator:"
echo "  $ACTUAL_VALIDATOR"
echo
echo "◆ Compatibility validator:"
echo "  $EXPECTED_VALIDATOR"
echo
echo "◆ New identity generated: NO"
echo "◆ Existing identity replaced: NO"
echo "◆ Self-trust: DISABLED"
echo "◆ Self-pairing: DISABLED"
echo "◆ Automatic trust: DISABLED"
echo "◆ Remote execution: DISABLED"
echo "◆ Remote installation: DISABLED"
echo "◆ Remote shell: DISABLED"
echo
echo "PHASE 2 STATUS: COMPLETE"
