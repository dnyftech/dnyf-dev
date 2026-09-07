#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

AUTHORITY="$ROOT/opt/dnyf/runtime/audit-ledger/dnyf-audit-security-ledger-authority.js"
CLI="$ROOT/bin/dnyf-audit"

BACKUP="$ROOT/backups/phase9d-ed25519-definitive/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$BACKUP"

cp -a "$AUTHORITY" "$BACKUP/dnyf-audit-security-ledger-authority.js"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 9D DEFINITIVE ED25519 AUTHORITY REPAIR"
echo "============================================================"
echo

echo "[1/7] Preserving active cryptographic authority..."

node - "$AUTHORITY" <<'NODE'
const authority = require(process.argv[2]);

const identity = authority.loadIdentity();

console.log("Device ID   :", identity.device_id);
console.log("Fingerprint :", identity.fingerprint);

if (
  identity.fingerprint !==
  "8a0cf45467dff43a76586033363561b643d6fa3c814f45e2a5fbd5ad61473e23"
) {
  throw new Error("ACTIVE_CRYPTOGRAPHIC_FINGERPRINT_CHANGED");
}

console.log("[OK] active Ed25519 authority preserved");
NODE

echo
echo "[2/7] Rebuilding Ed25519 signing implementation..."

python3 - "$AUTHORITY" <<'PY'
from pathlib import Path
import sys
import re

p = Path(sys.argv[1])
s = p.read_text()

# Remove unsupported Ed25519 dsaEncoding configuration.
s = s.replace("dsaEncoding: 'ieee-p1363'", "")
s = s.replace('dsaEncoding: "ieee-p1363"', "")

# Replace createSign based Ed25519 signing patterns.
patterns = [
    re.compile(
        r"const signer = crypto\.createSign\('SHA256'\);"
        r".*?"
        r"const signature = signer\.sign\(\{.*?\}\)\.toString\('base64'\);",
        re.S
    ),
    re.compile(
        r"const signer = crypto\.createSign\(\"SHA256\"\);"
        r".*?"
        r"const signature = signer\.sign\(\{.*?\}\)\.toString\(\"base64\"\);",
        re.S
    )
]

replacement_sign = """const signature = crypto.sign(
    null,
    Buffer.from(unsignedCanonical, 'utf8'),
    fs.readFileSync(PRIVATE_KEY_FILE)
  ).toString('base64');"""

for pattern in patterns:
    s = pattern.sub(replacement_sign, s)

# Replace createVerify based Ed25519 verification patterns.
verify_patterns = [
    re.compile(
        r"const verifier = crypto\.createVerify\('SHA256'\);"
        r".*?"
        r"const verified = verifier\.verify\(\s*\{.*?\},\s*Buffer\.from\(signature, 'base64'\)\s*\);",
        re.S
    ),
    re.compile(
        r"const verifier = crypto\.createVerify\(\"SHA256\"\);"
        r".*?"
        r"const verified = verifier\.verify\(\s*\{.*?\},\s*Buffer\.from\(signature, \"base64\"\)\s*\);",
        re.S
    )
]

replacement_verify = """const verified = crypto.verify(
    null,
    Buffer.from(canonicalUnsigned, 'utf8'),
    fs.readFileSync(PUBLIC_KEY_FILE),
    Buffer.from(signature, 'base64')
  );"""

for pattern in verify_patterns:
    s = pattern.sub(replacement_verify, s)

# Replace anchor signing if present.
anchor_patterns = [
    re.compile(
        r"const signer = crypto\.createSign\('SHA256'\);"
        r".*?"
        r"const signature = signer\.sign\(\{.*?\}\)\.toString\('base64'\);",
        re.S
    ),
    re.compile(
        r"const signer = crypto\.createSign\(\"SHA256\"\);"
        r".*?"
        r"const signature = signer\.sign\(\{.*?\}\)\.toString\(\"base64\"\);",
        re.S
    )
]

replacement_anchor = """const signature = crypto.sign(
    null,
    Buffer.from(canonicalJson(anchor), 'utf8'),
    fs.readFileSync(PRIVATE_KEY_FILE)
  ).toString('base64');"""

# Only apply anchor replacement where canonicalJson(anchor) occurs.
if "canonicalJson(anchor)" in s:
    for pattern in anchor_patterns:
        candidate = pattern.sub(replacement_anchor, s)
        if candidate != s:
            s = candidate
            break

# Hard security check: no unsupported Ed25519 encoding may remain.
if "ieee-p1363" in s:
    raise SystemExit("UNSUPPORTED_ED25519_ENCODING_REMAINS")

if "crypto.createSign('SHA256')" in s:
    raise SystemExit("LEGACY_ED25519_CREATE_SIGN_REMAINS")

if "crypto.createVerify('SHA256')" in s:
    raise SystemExit("LEGACY_ED25519_CREATE_VERIFY_REMAINS")

# Required native APIs must exist.
if "crypto.sign(" not in s:
    raise SystemExit("NATIVE_ED25519_SIGN_MISSING")

if "crypto.verify(" not in s:
    raise SystemExit("NATIVE_ED25519_VERIFY_MISSING")

p.write_text(s)
PY

chmod 600 "$AUTHORITY"

node --check "$AUTHORITY"

echo "[OK] authority patched"
echo "[OK] authority syntax valid"

echo
echo "[3/7] Confirming no legacy Ed25519 API remains..."

if grep -nE \
"ieee-p1363|createSign\(['\"]SHA256['\"]\)|createVerify\(['\"]SHA256['\"]\)" \
"$AUTHORITY"
then
  echo "[FAIL] legacy Ed25519 implementation remains"
  exit 1
fi

echo "[OK] no ieee-p1363"
echo "[OK] no legacy SHA256 Ed25519 signer"
echo "[OK] no legacy SHA256 Ed25519 verifier"

echo
echo "[4/7] Testing native Ed25519 signing..."

node - <<'NODE'
const crypto = require('crypto');

const { publicKey, privateKey } =
  crypto.generateKeyPairSync('ed25519');

const message = Buffer.from(
  'DNYFTECH-PHASE9D-DEFINITIVE-ED25519-TEST',
  'utf8'
);

const signature =
  crypto.sign(null, message, privateKey);

if (
  !crypto.verify(
    null,
    message,
    publicKey,
    signature
  )
) {
  throw new Error('ED25519_NATIVE_VERIFY_FAILED');
}

console.log('[OK] Ed25519 native sign');
console.log('[OK] Ed25519 native verify');
console.log('[OK] signature bytes:', signature.length);
NODE

echo
echo "[5/7] Testing DNYF audit authority..."

node "$CLI" test

echo
echo "[6/7] Verifying complete persisted ledger..."

node "$CLI" verify

echo
echo "[7/7] Verifying final authority fingerprint..."

node - "$AUTHORITY" <<'NODE'
const authority = require(process.argv[2]);

const identity = authority.loadIdentity();

if (
  identity.fingerprint !==
  "8a0cf45467dff43a76586033363561b643d6fa3c814f45e2a5fbd5ad61473e23"
) {
  throw new Error("CRYPTOGRAPHIC_FINGERPRINT_CHANGED");
}

const state = authority.loadState();
const records = authority.readRecords();

console.log("Device ID   :", identity.device_id);
console.log("Fingerprint :", identity.fingerprint);
console.log("Records     :", records.length);
console.log("Sequence    :", state.ledger_sequence);
console.log("Last hash   :", state.last_hash);

if (records.length > 0) {
  const last = records[records.length - 1];

  if (!last.signature) {
    throw new Error("PERSISTED_SIGNATURE_MISSING");
  }

  if (!last.record_hash) {
    throw new Error("PERSISTED_RECORD_HASH_MISSING");
  }
}

console.log("[OK] fingerprint unchanged");
console.log("[OK] persisted signed records valid");
console.log("[OK] ledger state consistent");
NODE

echo
echo "============================================================"
echo " PHASE 9D DEFINITIVE ED25519 REPAIR: PASS"
echo "============================================================"
echo
echo "Active fingerprint preserved:"
echo "8a0cf45467dff43a76586033363561b643d6fa3c814f45e2a5fbd5ad61473e23"
echo
echo "Backup:"
echo "${BACKUP#$ROOT/}"
echo
