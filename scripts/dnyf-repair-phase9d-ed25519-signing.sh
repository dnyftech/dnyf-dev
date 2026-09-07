#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

AUTHORITY="$ROOT/opt/dnyf/runtime/audit-ledger/dnyf-audit-security-ledger-authority.js"
CLI="$ROOT/bin/dnyf-audit"
STATE="$ROOT/opt/dnyf/state/audit-ledger"
LEDGER="$STATE/ledger/dnyf-security-audit-ledger.jsonl"
AUDIT_DIR="$STATE/audit"
BACKUP="$ROOT/backups/phase9d-ed25519-repair/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$BACKUP"

cp -a "$AUTHORITY" "$BACKUP/dnyf-audit-security-ledger-authority.js"

if [ -f "$LEDGER" ]; then
  cp -a "$LEDGER" "$BACKUP/dnyf-security-audit-ledger.jsonl"
fi

if [ -f "$STATE/local-audit-ledger-state.json" ]; then
  cp -a "$STATE/local-audit-ledger-state.json" "$BACKUP/local-audit-ledger-state.json"
fi

python3 - "$AUTHORITY" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

old_sign = """  const signer = crypto.createSign('SHA256');
  signer.update(unsignedCanonical);
  signer.end();

  const signature = signer.sign({
    key: fs.readFileSync(PRIVATE_KEY_FILE),
    dsaEncoding: 'ieee-p1363'
  }).toString('base64');"""

new_sign = """  const signature = crypto.sign(
    null,
    Buffer.from(unsignedCanonical, 'utf8'),
    fs.readFileSync(PRIVATE_KEY_FILE)
  ).toString('base64');"""

old_verify = """  const verifier = crypto.createVerify('SHA256');
  verifier.update(canonicalUnsigned);
  verifier.end();

  const verified = verifier.verify(
    {
      key: fs.readFileSync(PUBLIC_KEY_FILE),
      dsaEncoding: 'ieee-p1363'
    },
    Buffer.from(signature, 'base64')
  );"""

new_verify = """  const verified = crypto.verify(
    null,
    Buffer.from(canonicalUnsigned, 'utf8'),
    fs.readFileSync(PUBLIC_KEY_FILE),
    Buffer.from(signature, 'base64')
  );"""

old_anchor = """  const signer = crypto.createSign('SHA256');
  signer.update(canonicalJson(anchor));
  signer.end();

  const signature = signer.sign({
    key: fs.readFileSync(PRIVATE_KEY_FILE),
    dsaEncoding: 'ieee-p1363'
  }).toString('base64');"""

new_anchor = """  const signature = crypto.sign(
    null,
    Buffer.from(canonicalJson(anchor), 'utf8'),
    fs.readFileSync(PRIVATE_KEY_FILE)
  ).toString('base64');"""

if old_sign not in s:
    raise SystemExit("signing block not found")

if old_verify not in s:
    raise SystemExit("verification block not found")

if old_anchor not in s:
    raise SystemExit("anchor signing block not found")

s = s.replace(old_sign, new_sign)
s = s.replace(old_verify, new_verify)
s = s.replace(old_anchor, new_anchor)

p.write_text(s)
PY

chmod 600 "$AUTHORITY"

node --check "$AUTHORITY"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 9D ED25519 CRYPTO REPAIR"
echo "============================================================"
echo
echo "Authority: ${AUTHORITY#$ROOT/}"
echo

echo "[1/6] Checking active Ed25519 authority..."

node - "$AUTHORITY" <<'NODE'
const authority = require(process.argv[2]);

const identity = authority.loadIdentity();

if (!identity.device_id) {
  throw new Error('device-id-missing');
}

console.log('[OK] active identity:', identity.device_id);
console.log('[OK] active fingerprint:', identity.fingerprint);
NODE

echo
echo "[2/6] Testing native Ed25519 sign/verify compatibility..."

node - <<'NODE'
const crypto = require('crypto');

const { publicKey, privateKey } =
  crypto.generateKeyPairSync('ed25519');

const message =
  Buffer.from('DNYFTECH-PHASE9D-ED25519-COMPATIBILITY');

const signature =
  crypto.sign(null, message, privateKey);

if (!crypto.verify(null, message, publicKey, signature)) {
  throw new Error('ed25519-signature-verification-failed');
}

console.log('[OK] native Ed25519 sign/verify');
console.log('[OK] signature bytes:', signature.length);
NODE

echo
echo "[3/6] Testing DNYF audit authority..."

TEST_OUTPUT="$(
  node "$CLI" test 2>&1
)" || {
  echo "$TEST_OUTPUT"
  echo
  echo "[FAIL] DNYF audit authority test"
  exit 1
}

echo "$TEST_OUTPUT"

echo
echo "[4/6] Verifying persisted ledger..."

VERIFY_OUTPUT="$(
  node "$CLI" verify 2>&1
)"

echo "$VERIFY_OUTPUT"

if ! printf '%s\n' "$VERIFY_OUTPUT" | grep -Fq '"ok": true'; then
  echo "[FAIL] ledger verification"
  exit 1
fi

echo "[OK] persisted ledger verification"

echo
echo "[5/6] Verifying restart-safe state..."

node - "$AUTHORITY" <<'NODE'
const authority = require(process.argv[2]);

const state = authority.loadState();
const records = authority.readRecords();

if (records.length < 1) {
  throw new Error('expected-persisted-record');
}

const last = records[records.length - 1];

if (state.ledger_sequence !== last.ledger_sequence) {
  throw new Error('state-sequence-mismatch');
}

if (state.last_hash !== last.record_hash) {
  throw new Error('state-hash-mismatch');
}

if (last.signature === undefined || !last.signature) {
  throw new Error('persisted-signature-missing');
}

if (last.record_hash === undefined || !last.record_hash) {
  throw new Error('persisted-record-hash-missing');
}

console.log('[OK] persisted sequence');
console.log('[OK] persisted last hash');
console.log('[OK] persisted signature');
console.log('[OK] persisted record hash');
NODE

echo
echo "[6/6] Final status..."

node "$CLI" status

echo
echo "============================================================"
echo " PHASE 9D ED25519 CRYPTO REPAIR: PASS"
echo "============================================================"
echo
echo "Backup: ${BACKUP#$ROOT/}"
echo
echo "The active Ed25519 keypair was preserved."
echo "No cryptographic authority was regenerated."
echo
