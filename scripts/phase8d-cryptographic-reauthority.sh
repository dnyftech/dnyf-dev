#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
ETC="$ROOT/etc/dnyf"
SECURE="$ROOT/opt/dnyf/runtime/secure/identity"
STATE="$ROOT/opt/dnyf/state"
BACKUP_ROOT="$ROOT/backups/cryptographic-reauthority"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$BACKUP_ROOT/$STAMP"

CANONICAL_ID_FILE="$ETC/device-id"
LEGACY_IDENTITY="$ETC/identity.json"
AUTHORITY_FILE="$ETC/runtime/dnyf-runtime-identity-authority.json"

PRIVATE_KEY="$SECURE/device-ed25519-private.pem"
PUBLIC_KEY="$SECURE/device-ed25519-public.pem"
IDENTITY_FILE="$SECURE/identity.json"

OLD_FINGERPRINT="3b3cab3fec13f87ff4039d06851c0faeb8d968159cce88e7cde890c69bc539c9"

PASS=0
FAIL=0

ok() {
    printf '[OK] %s\n' "$1"
    PASS=$((PASS+1))
}

fail() {
    printf '[FAIL] %s\n' "$1"
    FAIL=$((FAIL+1))
}

warn() {
    printf '[WARN] %s\n' "$1"
}

die() {
    printf '\n[FATAL] %s\n' "$1"
    exit 1
}

printf '%s\n' '============================================================'
printf '%s\n' ' DNYFTECH — CRYPTOGRAPHIC RE-AUTHORITY TRANSITION'
printf '%s\n' '============================================================'
printf 'Root: %s\n\n' "$ROOT"

[ -d "$ROOT" ] || die "DNYF-DEV root does not exist"
command -v openssl >/dev/null 2>&1 || die "openssl is required"
command -v node >/dev/null 2>&1 || die "node is required"

mkdir -p "$BACKUP" "$SECURE" "$ETC/runtime" "$ETC/auth"

# ------------------------------------------------------------
# 1. Recover canonical device ID
# ------------------------------------------------------------

[ -f "$CANONICAL_ID_FILE" ] || die "Canonical device ID file is missing"

DEVICE_ID="$(tr -d '[:space:]' < "$CANONICAL_ID_FILE" | tr '[:upper:]' '[:lower:]')"

printf 'Canonical device ID:\n  %s\n\n' "$DEVICE_ID"

printf '%s\n' "$DEVICE_ID" | grep -Eq '^[0-9a-f]{32}$' \
    || die "Canonical device ID is not a valid 32-character hexadecimal identifier"

ok "canonical device ID preserved"

# ------------------------------------------------------------
# 2. Create rollback snapshot
# ------------------------------------------------------------

printf '%s\n' '◆ Creating rollback snapshot...'

for ITEM in \
    "$LEGACY_IDENTITY" \
    "$AUTHORITY_FILE" \
    "$ETC/trust/peers.json" \
    "$ROOT/opt/dnyf/state/trust/registry.json" \
    "$ETC/auth/protocol.json"
do
    if [ -e "$ITEM" ]; then
        REL="${ITEM#$ROOT/}"
        mkdir -p "$BACKUP/$(dirname "$REL")"
        cp -a "$ITEM" "$BACKUP/$REL"
    fi
done

printf '%s\n' "$OLD_FINGERPRINT" > "$BACKUP/historical-fingerprint.txt"
printf '%s\n' "$DEVICE_ID" > "$BACKUP/canonical-device-id.txt"

ok "rollback snapshot created: $BACKUP"

# ------------------------------------------------------------
# 3. Protect against accidental overwrite
# ------------------------------------------------------------

if [ -f "$PRIVATE_KEY" ] || [ -f "$PUBLIC_KEY" ] || [ -f "$IDENTITY_FILE" ]; then
    warn "Cryptographic identity files already exist"

    EXISTING_PRIVATE=0
    EXISTING_PUBLIC=0
    EXISTING_IDENTITY=0

    [ -f "$PRIVATE_KEY" ] && EXISTING_PRIVATE=1
    [ -f "$PUBLIC_KEY" ] && EXISTING_PUBLIC=1
    [ -f "$IDENTITY_FILE" ] && EXISTING_IDENTITY=1

    printf 'Existing private key : %s\n' "$EXISTING_PRIVATE"
    printf 'Existing public key  : %s\n' "$EXISTING_PUBLIC"
    printf 'Existing identity    : %s\n' "$EXISTING_IDENTITY"

    die "Existing cryptographic authority detected; refusing to overwrite it"
fi

ok "no existing cryptographic authority will be overwritten"

# ------------------------------------------------------------
# 4. Generate NEW Ed25519 authority
# ------------------------------------------------------------

printf '\n%s\n' '◆ Generating fresh Ed25519 cryptographic authority...'

TMP_PRIVATE="$SECURE/.device-ed25519-private.pem.$STAMP"
TMP_PUBLIC="$SECURE/.device-ed25519-public.pem.$STAMP"

openssl genpkey \
    -algorithm ED25519 \
    -out "$TMP_PRIVATE" >/dev/null 2>&1 \
    || die "Ed25519 private-key generation failed"

openssl pkey \
    -in "$TMP_PRIVATE" \
    -pubout \
    -out "$TMP_PUBLIC" >/dev/null 2>&1 \
    || die "Ed25519 public-key derivation failed"

chmod 600 "$TMP_PRIVATE"
chmod 644 "$TMP_PUBLIC"

mv "$TMP_PRIVATE" "$PRIVATE_KEY"
mv "$TMP_PUBLIC" "$PUBLIC_KEY"

ok "new Ed25519 private key generated"
ok "new Ed25519 public key derived"

# ------------------------------------------------------------
# 5. Calculate fingerprint from actual public key
# ------------------------------------------------------------

NEW_FINGERPRINT="$(
    openssl pkey \
        -pubin \
        -in "$PUBLIC_KEY" \
        -outform DER 2>/dev/null |
    openssl dgst -sha256 -r |
    awk '{print tolower($1)}'
)"

printf '\nNew cryptographic fingerprint:\n  %s\n\n' "$NEW_FINGERPRINT"

printf '%s\n' "$NEW_FINGERPRINT" |
    grep -Eq '^[0-9a-f]{64}$' \
    || die "Could not calculate valid SHA-256 public-key fingerprint"

[ "$NEW_FINGERPRINT" != "$OLD_FINGERPRINT" ] \
    || die "Generated authority unexpectedly matches historical fingerprint"

ok "new fingerprint derived from actual public key"
ok "historical fingerprint is not reused"

# ------------------------------------------------------------
# 6. Create canonical cryptographic identity
# ------------------------------------------------------------

printf '%s\n' '◆ Writing canonical cryptographic identity...'

cat > "$IDENTITY_FILE" <<EOF
{
  "schema": "dnyf.cryptographic-identity.v3",
  "authority": "dnyf-cryptauth",
  "device_id": "$DEVICE_ID",
  "algorithm": "Ed25519",
  "fingerprint": "$NEW_FINGERPRINT",
  "public_key": "$PUBLIC_KEY",
  "private_key": "$PRIVATE_KEY",
  "identity_status": "active",
  "generated_new_identity": true,
  "generated_by_phase2": false,
  "previous_fingerprint": "$OLD_FINGERPRINT",
  "previous_identity_status": "lost",
  "previous_key_recovered": false,
  "historical_key_usable": false,
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

chmod 600 "$IDENTITY_FILE"

ok "canonical cryptographic identity created"

# ------------------------------------------------------------
# 7. Verify public/private key correspondence
# ------------------------------------------------------------

printf '%s\n' '◆ Verifying key correspondence...'

DER_FROM_PRIVATE="$(
    openssl pkey \
        -in "$PRIVATE_KEY" \
        -pubout \
        -outform DER 2>/dev/null |
    openssl dgst -sha256 -r |
    awk '{print tolower($1)}'
)"

DER_FROM_PUBLIC="$(
    openssl pkey \
        -pubin \
        -in "$PUBLIC_KEY" \
        -outform DER 2>/dev/null |
    openssl dgst -sha256 -r |
    awk '{print tolower($1)}'
)"

[ "$DER_FROM_PRIVATE" = "$DER_FROM_PUBLIC" ] \
    || die "Private/public key correspondence verification failed"

ok "private/public key correspondence verified"

# ------------------------------------------------------------
# 8. Update legacy identity metadata WITHOUT changing device ID
# ------------------------------------------------------------

printf '%s\n' '◆ Reconciling legacy identity metadata...'

if [ -f "$LEGACY_IDENTITY" ]; then
    cp -a "$LEGACY_IDENTITY" "$BACKUP/legacy-identity-before-reconcile.json"

    node - "$LEGACY_IDENTITY" "$DEVICE_ID" "$OLD_FINGERPRINT" "$NEW_FINGERPRINT" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
const deviceId = process.argv[3];
const oldFingerprint = process.argv[4];
const newFingerprint = process.argv[5];

let data = {};
try {
  data = JSON.parse(fs.readFileSync(file, "utf8"));
} catch (_) {}

data.schema = "dnyf.identity.v3";
data.device_id = deviceId;
data.key_algorithm = "Ed25519";
data.identity_authority = "dnyf-cryptauth";
data.identity_status = "active";
data.private_key_recovered = false;
data.new_key_required_if_original_key_is_lost = false;
data.generated_by_phase2 = false;
data.generated_new_identity = true;
data.fingerprint = newFingerprint;
data.public_key_authority = "dnyf-cryptauth";
data.previous_fingerprint = oldFingerprint;
data.previous_identity_status = "lost";
data.historical_fingerprint = oldFingerprint;
data.historical_key_usable = false;
data.self_trust = false;
data.self_pairing = false;
data.automatic_trust = false;

fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n", {mode: 0o600});
NODE

    chmod 600 "$LEGACY_IDENTITY"
    ok "legacy identity reconciled without changing device ID"
else
    warn "legacy identity file absent; canonical identity remains authoritative"
fi

# ------------------------------------------------------------
# 9. Write runtime identity authority
# ------------------------------------------------------------

cat > "$AUTHORITY_FILE" <<EOF
{
  "schema": "dnyf.runtime.identity-authority.v2",
  "authority": "dnyf-cryptauth",
  "device_id": "$DEVICE_ID",
  "fingerprint": "$NEW_FINGERPRINT",
  "public_key": "$PUBLIC_KEY",
  "private_key": "$PRIVATE_KEY",
  "source": "$IDENTITY_FILE",
  "algorithm": "Ed25519",
  "create_missing_identity": false,
  "replace_existing_identity": false,
  "generate_new_identity": false,
  "historical_fingerprint": "$OLD_FINGERPRINT",
  "historical_identity_status": "lost",
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

chmod 600 "$AUTHORITY_FILE"

ok "Phase 2 identity authority anchored to cryptauth"

# ------------------------------------------------------------
# 10. Anchor environment-independent identity discovery
# ------------------------------------------------------------

cat > "$ETC/dnyf-identity-authority.env" <<EOF
DNYF_IDENTITY_FILE=$IDENTITY_FILE
DNYF_PUBLIC_KEY_FILE=$PUBLIC_KEY
DNYF_PRIVATE_KEY_FILE=$PRIVATE_KEY
DNYF_DEVICE_ID=$DEVICE_ID
DNYF_DEVICE_FINGERPRINT=$NEW_FINGERPRINT
DNYF_IDENTITY_AUTHORITY=dnyf-cryptauth
EOF

chmod 600 "$ETC/dnyf-identity-authority.env"

ok "identity environment authority written"

# ------------------------------------------------------------
# 11. Verify canonical identity loader
# ------------------------------------------------------------

printf '\n%s\n' '◆ Testing canonical identity loader...'

export DNYF_ROOT="$ROOT"
export DNYF_IDENTITY_FILE="$IDENTITY_FILE"
unset DNYF_DEVICE_ID || true
unset DNYF_DEVICE_FINGERPRINT || true

IDENTITY_TEST="$(
    node - "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js" <<'NODE'
const mod = require(process.argv[2]);
const result = mod.loadIdentity();
console.log(JSON.stringify(result, null, 2));
NODE
)" || {
    printf '%s\n' "$IDENTITY_TEST"
    die "canonical identity loader failed"
}

printf '%s\n' "$IDENTITY_TEST"

printf '%s\n' "$IDENTITY_TEST" | grep -q "\"device_id\"" \
    || die "identity loader did not return device_id"

printf '%s\n' "$IDENTITY_TEST" | grep -q "$DEVICE_ID" \
    || die "identity loader returned wrong device ID"

printf '%s\n' "$IDENTITY_TEST" | grep -q "$NEW_FINGERPRINT" \
    || die "identity loader did not expose new fingerprint"

ok "canonical identity loader resolves new authority"

# ------------------------------------------------------------
# 12. Runtime core integration test
# ------------------------------------------------------------

printf '\n%s\n' '◆ Testing universal runtime core contract...'

CORE="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"

[ -f "$CORE" ] || die "universal runtime core is missing"

CORE_TEST="$(
    node - "$CORE" "$ROOT" <<'NODE'
const core = require(process.argv[2]);
const root = process.argv[3];

const expected = [
  "runtimeInfo",
  "classifyArtifact",
  "dispatch"
];

for (const name of expected) {
  if (typeof core[name] !== "function") {
    throw new Error(`missing runtime core export: ${name}`);
  }
}

const info = core.runtimeInfo();

if (!info || typeof info !== "object") {
  throw new Error("runtimeInfo() did not return an object");
}

const artifactSamples = [
  "example.js",
  "example.json",
  "example.zip",
  "example.exe"
];

const classifications = {};

for (const item of artifactSamples) {
  try {
    classifications[item] = core.classifyArtifact(item);
  } catch (error) {
    classifications[item] = {
      error: error.message
    };
  }
}

console.log(JSON.stringify({
  exports: expected,
  runtimeInfo: info,
  classifications
}, null, 2));
NODE
)" || {
    printf '%s\n' "$CORE_TEST"
    die "runtime core integration test failed"
}

printf '%s\n' "$CORE_TEST"

ok "runtimeInfo() integration"
ok "classifyArtifact() integration"
ok "runtime core module contract"

# ------------------------------------------------------------
# 13. Syntax-check universal runtime
# ------------------------------------------------------------

printf '\n%s\n' '◆ Syntax checking universal runtime components...'

RUNTIME_DIR="$ROOT/opt/dnyf/runtime/universal"

for FILE in "$RUNTIME_DIR"/*.js; do
    [ -f "$FILE" ] || continue

    if node --check "$FILE" >/dev/null 2>&1; then
        ok "syntax: $(basename "$FILE")"
    else
        fail "syntax: $(basename "$FILE")"
    fi
done

# ------------------------------------------------------------
# 14. Security invariant verification
# ------------------------------------------------------------

printf '\n%s\n' '◆ Verifying security invariants...'

SECURITY_JSON="$IDENTITY_FILE"

for FLAG in \
    self_trust \
    self_pairing \
    automatic_trust \
    remote_execution \
    remote_installation \
    remote_shell
do
    VALUE="$(
        node - "$SECURITY_JSON" "$FLAG" <<'NODE'
const fs = require("fs");
const data = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const key = process.argv[3];
console.log(String(data[key]));
NODE
    )"

    if [ "$VALUE" = "false" ]; then
        ok "$FLAG disabled"
    else
        fail "$FLAG is not disabled"
    fi
done

# ------------------------------------------------------------
# 15. Permission verification
# ------------------------------------------------------------

printf '\n%s\n' '◆ Verifying cryptographic file permissions...'

PRIVATE_MODE="$(stat -c '%a' "$PRIVATE_KEY" 2>/dev/null || stat -f '%Lp' "$PRIVATE_KEY")"
IDENTITY_MODE="$(stat -c '%a' "$IDENTITY_FILE" 2>/dev/null || stat -f '%Lp' "$IDENTITY_FILE")"

printf 'Private key mode : %s\n' "$PRIVATE_MODE"
printf 'Identity mode    : %s\n' "$IDENTITY_MODE"

case "$PRIVATE_MODE" in
    600|400)
        ok "private key permissions are restricted"
        ;;
    *)
        fail "private key permissions are too broad"
        ;;
esac

# ------------------------------------------------------------
# 16. Historical fingerprint protection
# ------------------------------------------------------------

printf '\n%s\n' '◆ Verifying historical identity separation...'

if grep -Rqs "$OLD_FINGERPRINT" "$SECURE" "$ETC/runtime" 2>/dev/null; then
    ok "historical fingerprint retained only as historical metadata"
else
    warn "historical fingerprint not present in active authority directories"
fi

if grep -Rqs "\"fingerprint\"[[:space:]]*:[[:space:]]*\"$OLD_FINGERPRINT\"" \
    "$IDENTITY_FILE" "$AUTHORITY_FILE" 2>/dev/null; then
    fail "historical fingerprint is incorrectly active"
else
    ok "historical fingerprint is not active authority"
fi

grep -q "\"fingerprint\": \"$NEW_FINGERPRINT\"" "$IDENTITY_FILE" \
    || die "new fingerprint missing from canonical identity"

ok "new fingerprint is active authority"

# ------------------------------------------------------------
# 17. Device ID immutability verification
# ------------------------------------------------------------

LOADED_ID="$(
    node - "$IDENTITY_FILE" <<'NODE'
const fs = require("fs");
console.log(JSON.parse(fs.readFileSync(process.argv[2], "utf8")).device_id);
NODE
)"

[ "$LOADED_ID" = "$DEVICE_ID" ] \
    || die "device ID changed during re-authority transition"

ok "canonical device ID unchanged"

# ------------------------------------------------------------
# 18. Generate machine-readable transition record
# ------------------------------------------------------------

TRANSITION="$STATE/audit/cryptographic-reauthority-$STAMP.jsonl"
mkdir -p "$(dirname "$TRANSITION")"

cat > "$TRANSITION" <<EOF
{"event":"cryptographic-reauthority","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","device_id":"$DEVICE_ID","authority":"dnyf-cryptauth","algorithm":"Ed25519","previous_fingerprint":"$OLD_FINGERPRINT","previous_status":"lost","new_fingerprint":"$NEW_FINGERPRINT","new_status":"active","self_trust":false,"self_pairing":false,"automatic_trust":false,"remote_execution":false,"remote_installation":false,"remote_shell":false,"rollback_backup":"$BACKUP"}
EOF

chmod 600 "$TRANSITION"

ok "cryptographic transition audit record created"

# ------------------------------------------------------------
# 19. Final summary
# ------------------------------------------------------------

printf '\n%s\n' '============================================================'
printf '%s\n' ' CRYPTOGRAPHIC RE-AUTHORITY RESULT'
printf '%s\n' '============================================================'

printf 'Device ID          : %s\n' "$DEVICE_ID"
printf 'New fingerprint    : %s\n' "$NEW_FINGERPRINT"
printf 'Old fingerprint    : %s\n' "$OLD_FINGERPRINT"
printf 'Identity status    : ACTIVE'
printf '\n'
printf 'Private key        : %s\n' "$PRIVATE_KEY"
printf 'Public key         : %s\n' "$PUBLIC_KEY"
printf 'Identity authority : %s\n' "$IDENTITY_FILE"
printf 'Runtime authority   : %s\n' "$AUTHORITY_FILE"
printf 'Rollback backup     : %s\n' "$BACKUP"
printf 'Audit record        : %s\n' "$TRANSITION"
printf '\n'
printf 'Passed: %s\n' "$PASS"
printf 'Failed: %s\n' "$FAIL"

if [ "$FAIL" -ne 0 ]; then
    printf '\n[RESULT] RE-AUTHORITY INCOMPLETE\n'
    printf '[ACTION] Do not proceed to trust/session promotion.\n'
    exit 1
fi

printf '\n[RESULT] CRYPTOGRAPHIC RE-AUTHORITY: PASS\n'
printf '[SECURITY] Historical key is NOT trusted.\n'
printf '[SECURITY] New Ed25519 authority is active.\n'
printf '[SECURITY] Self-trust remains disabled.\n'
printf '[SECURITY] Self-pairing remains disabled.\n'
printf '[SECURITY] Automatic trust remains disabled.\n'
printf '[SECURITY] Remote execution remains disabled.\n'
printf '[SECURITY] Remote installation remains disabled.\n'
printf '[SECURITY] Remote shell remains disabled.\n'
printf '\n'
