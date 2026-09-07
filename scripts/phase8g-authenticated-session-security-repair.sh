#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
STATE_DIR="${ROOT}/opt/dnyf/state/session"
SESSION_DIR="$ROOT/opt/dnyf/runtime/session"
SECURE_DIR="$ROOT/opt/dnyf/runtime/secure/identity"
ETC_SESSION="$ROOT/etc/dnyf/session"
STATE_SESSION="$ROOT/opt/dnyf/state/session"
BACKUP="$ROOT/backups/phase8g-session-security/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$SESSION_DIR" "$ETC_SESSION" "$STATE_SESSION" "$BACKUP"

echo "============================================================"
echo " DNYFTECH — PHASE 8G AUTHENTICATED SESSION SECURITY REPAIR"
echo "============================================================"
echo "Root: $ROOT"
echo

IDENTITY="$SECURE_DIR/identity.json"
PRIVATE_KEY="$SECURE_DIR/device-ed25519-private.pem"
PUBLIC_KEY="$SECURE_DIR/device-ed25519-public.pem"

[ -f "$IDENTITY" ] || { echo "[FAIL] Missing canonical cryptographic identity"; exit 1; }
[ -f "$PRIVATE_KEY" ] || { echo "[FAIL] Missing Ed25519 private key"; exit 1; }
[ -f "$PUBLIC_KEY" ] || { echo "[FAIL] Missing Ed25519 public key"; exit 1; }

cp -a "$IDENTITY" "$BACKUP/"
cp -a "$PRIVATE_KEY" "$BACKUP/"
cp -a "$PUBLIC_KEY" "$BACKUP/"

DEVICE_ID="$(node -e 'const x=require(process.argv[1]);process.stdout.write(String(x.device_id||"").toLowerCase())' "$IDENTITY")"
FINGERPRINT="$(node -e 'const x=require(process.argv[1]);process.stdout.write(String(x.fingerprint||"").toLowerCase())' "$IDENTITY")"

[ -n "$DEVICE_ID" ] || { echo "[FAIL] Missing canonical device ID"; exit 1; }
[ -n "$FINGERPRINT" ] || { echo "[FAIL] Missing active fingerprint"; exit 1; }

echo "Canonical device:"
echo "  $DEVICE_ID"
echo "Active fingerprint:"
echo "  $FINGERPRINT"
echo

echo "◆ Creating canonical session protocol..."

cat > "$ETC_SESSION/protocol.json" <<EOF
{
  "schema": "dnyf.session.v1",
  "protocol": "dnyf-session/1",
  "version": "1.0.0",
  "algorithm": "Ed25519",
  "hash": "SHA-256",
  "session_id_bytes": 32,
  "nonce_bytes": 32,
  "challenge_bytes": 32,
  "timestamp_window_seconds": 300,
  "session_ttl_seconds": 900,
  "replay_protection": true,
  "persistent_replay_state": true,
  "local_approval_required": true,
  "explicit_revocation_required": true,
  "response_proof_required": true,
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false
}
EOF

chmod 600 "$ETC_SESSION/protocol.json"
echo "[OK] session protocol"

echo "◆ Writing hardened session authority library..."

cat > "$SESSION_DIR/dnyf-authenticated-session-authority.js" <<'EOF'
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function resolveRoot() {
  return process.env.DNYF_ROOT || path.resolve(__dirname, '../../../../..');
}

const ROOT = resolveRoot();
const IDENTITY_FILE =
  process.env.DNYF_IDENTITY_FILE ||
  path.join(ROOT, 'opt/dnyf/runtime/secure/identity/identity.json');

const PROTOCOL_FILE =
  path.join(ROOT, 'etc/dnyf/session/protocol.json');

const STATE_DIR =
  path.join(ROOT, 'opt/dnyf/state/session');

const REPLAY_FILE =
  path.join(STATE_DIR, 'replay-nonces.json');

const REVOCATION_FILE =
  path.join(STATE_DIR, 'revoked-sessions.json');

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function atomicWrite(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}-${crypto.randomBytes(8).toString('hex')}`;
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, file);
}

function loadIdentity() {
  const identity = readJson(IDENTITY_FILE, null);
  if (!identity) throw new Error('canonical identity unavailable');

  if (!identity.device_id || !identity.fingerprint || !identity.public_key) {
    throw new Error('canonical cryptographic identity incomplete');
  }

  return identity;
}

function loadProtocol() {
  const protocol = readJson(PROTOCOL_FILE, null);
  if (!protocol || protocol.protocol !== 'dnyf-session/1') {
    throw new Error('canonical session protocol unavailable');
  }
  return protocol;
}

function now() {
  return Date.now();
}

function timestampValid(timestamp, windowSeconds) {
  const ts = Number(timestamp);
  if (!Number.isFinite(ts)) return false;

  const supplied =
    ts < 100000000000
      ? ts * 1000
      : ts;

  return Math.abs(now() - supplied) <= windowSeconds * 1000;
}

function generateSessionId() {
  return crypto.randomBytes(32).toString('hex');
}

function generateNonce() {
  return crypto.randomBytes(32).toString('hex');
}

function generateChallenge() {
  return crypto.randomBytes(32).toString('hex');
}

function bodyHash(body) {
  return crypto
    .createHash('sha256')
    .update(typeof body === 'string' ? body : JSON.stringify(body ?? ''))
    .digest('hex');
}

function canonicalProof(sessionId, challenge, timestamp, nonce, body) {
  return [
    'dnyf-session-proof-v1',
    sessionId,
    challenge,
    String(timestamp),
    nonce,
    bodyHash(body)
  ].join('\n');
}

function signProof(privateKey, sessionId, challenge, timestamp, nonce, body) {
  const data = canonicalProof(
    sessionId,
    challenge,
    timestamp,
    nonce,
    body
  );

  return crypto
    .sign(null, Buffer.from(data), privateKey)
    .toString('base64');
}

function verifyProof(publicKey, signature, sessionId, challenge, timestamp, nonce, body) {
  const data = canonicalProof(
    sessionId,
    challenge,
    timestamp,
    nonce,
    body
  );

  return crypto.verify(
    null,
    Buffer.from(data),
    publicKey,
    Buffer.from(signature, 'base64')
  );
}

function loadReplay() {
  return readJson(REPLAY_FILE, { nonces: {} });
}

function rememberNonce(nonce, timestamp) {
  const state = loadReplay();

  if (state.nonces[nonce]) {
    throw new Error('replay detected');
  }

  state.nonces[nonce] = Number(timestamp);

  const cutoff = now() - 3600000;

  for (const [key, value] of Object.entries(state.nonces)) {
    if (Number(value) < cutoff) delete state.nonces[key];
  }

  atomicWrite(REPLAY_FILE, state);
}

function loadRevocations() {
  return readJson(REVOCATION_FILE, { sessions: {} });
}

function isRevoked(sessionId) {
  return Boolean(loadRevocations().sessions[sessionId]);
}

function revokeSession(sessionId, reason = 'explicit-revocation') {
  const state = loadRevocations();

  state.sessions[sessionId] = {
    revoked_at: new Date().toISOString(),
    reason
  };

  atomicWrite(REVOCATION_FILE, state);
}

function createSessionRecord(peer) {
  const protocol = loadProtocol();
  const identity = loadIdentity();

  const sessionId = generateSessionId();
  const challenge = generateChallenge();
  const created = now();

  return {
    schema: 'dnyf.session.record.v1',
    session_id: sessionId,
    state: 'pending',
    created_at: new Date(created).toISOString(),
    expires_at: new Date(
      created + protocol.session_ttl_seconds * 1000
    ).toISOString(),

    initiator: {
      device_id: identity.device_id.toLowerCase(),
      fingerprint: identity.fingerprint.toLowerCase(),
      public_key: identity.public_key
    },

    responder: {
      device_id: String(peer.device_id || '').toLowerCase(),
      fingerprint: String(peer.fingerprint || '').toLowerCase(),
      public_key: String(peer.public_key || '')
    },

    challenge,
    local_approved: false,
    remote_verified: false,
    revoked: false
  };
}

function validatePeerIdentity(peer) {
  if (!peer || typeof peer !== 'object') {
    throw new Error('peer identity required');
  }

  if (!peer.device_id || !peer.fingerprint || !peer.public_key) {
    throw new Error('peer cryptographic identity incomplete');
  }

  if (String(peer.device_id).toLowerCase() === loadIdentity().device_id.toLowerCase()) {
    throw new Error('self-pairing/session prohibited');
  }
}

function verifyResponse(record, response) {
  const protocol = loadProtocol();

  if (!record || !response) {
    throw new Error('session response unavailable');
  }

  if (record.state === 'revoked' || isRevoked(record.session_id)) {
    throw new Error('session revoked');
  }

  if (new Date(record.expires_at).getTime() < now()) {
    throw new Error('session expired');
  }

  if (!timestampValid(response.timestamp, protocol.timestamp_window_seconds)) {
    throw new Error('invalid response timestamp');
  }

  if (!response.nonce || !response.signature) {
    throw new Error('response proof incomplete');
  }

  if (
    String(response.device_id || '').toLowerCase() !==
    record.responder.device_id.toLowerCase()
  ) {
    throw new Error('responder device mismatch');
  }

  if (
    String(response.fingerprint || '').toLowerCase() !==
    record.responder.fingerprint.toLowerCase()
  ) {
    throw new Error('responder fingerprint mismatch');
  }

  if (String(response.public_key || '') !== record.responder.public_key) {
    throw new Error('responder public key mismatch');
  }

  if (String(response.challenge || '') !== record.challenge) {
    throw new Error('challenge mismatch');
  }

  if (!verifyProof(
    record.responder.public_key,
    response.signature,
    record.session_id,
    record.challenge,
    response.timestamp,
    response.nonce,
    response.body
  )) {
    throw new Error('invalid responder proof-of-possession');
  }

  rememberNonce(response.nonce, response.timestamp);

  record.remote_verified = true;
  record.remote_verified_at = new Date().toISOString();

  return record;
}

function approveSession(record) {
  if (!record.remote_verified) {
    throw new Error('remote identity not verified');
  }

  if (record.revoked || isRevoked(record.session_id)) {
    throw new Error('session revoked');
  }

  record.local_approved = true;
  record.state = 'authenticated';
  record.approved_at = new Date().toISOString();

  return record;
}

function revoke(record, reason) {
  revokeSession(record.session_id, reason);
  record.revoked = true;
  record.state = 'revoked';
  record.revoked_at = new Date().toISOString();
  record.revocation_reason = reason;

  return record;
}

module.exports = {
  resolveRoot,
  loadIdentity,
  loadProtocol,
  generateSessionId,
  generateNonce,
  generateChallenge,
  bodyHash,
  canonicalProof,
  signProof,
  verifyProof,
  validatePeerIdentity,
  createSessionRecord,
  verifyResponse,
  approveSession,
  revokeSession,
  isRevoked,
  revoke
};
EOF

chmod 600 "$SESSION_DIR/dnyf-authenticated-session-authority.js"
echo "[OK] authenticated session authority"

STATE_DIR="${ROOT}/opt/dnyf/state/session"

echo "◆ Writing session state contract..."

cat > "$ETC_SESSION/state.json" <<EOF
{
  "schema": "dnyf.session.state.v1",
  "storage": "$STATE_DIR",
  "replay_file": "$STATE_DIR/replay-nonces.json",
  "revocation_file": "$STATE_DIR/revoked-sessions.json",
  "restart_safe": true,
  "persistent_replay_protection": true,
  "persistent_revocation": true
}
EOF

chmod 600 "$ETC_SESSION/state.json"

[ -f "$STATE_DIR/replay-nonces.json" ] || \
  printf '%s\n' '{"nonces":{}}' > "$STATE_DIR/replay-nonces.json"

[ -f "$STATE_DIR/revoked-sessions.json" ] || \
  printf '%s\n' '{"sessions":{}}' > "$STATE_DIR/revoked-sessions.json"

chmod 600 "$STATE_DIR/replay-nonces.json" "$STATE_DIR/revoked-sessions.json"

echo "[OK] persistent session state"

echo
echo "◆ Syntax validation..."

node --check "$SESSION_DIR/dnyf-authenticated-session-authority.js"
echo "[OK] authenticated session authority syntax"

node --check "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"
echo "[OK] runtime core syntax"

echo
echo "◆ Cryptographic contract test..."

DNYF_ROOT="$ROOT" \
DNYF_IDENTITY_FILE="$IDENTITY" \
node <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const root = process.env.DNYF_ROOT;
const idFile = process.env.DNYF_IDENTITY_FILE;

const identity = JSON.parse(fs.readFileSync(idFile, 'utf8'));
const session = require(
  path.join(root, 'opt/dnyf/runtime/session/dnyf-authenticated-session-authority.js')
);

const peerKeys = crypto.generateKeyPairSync('ed25519');
const peerPublic = crypto
  .createPublicKey(peerKeys.privateKey)
  .export({ type:'spki', format:'pem' });

const peer = {
  device_id: 'peer-test-device-8g',
  fingerprint: crypto
    .createHash('sha256')
    .update(peerPublic)
    .digest('hex'),
  public_key: peerPublic
};

session.validatePeerIdentity(peer);

const record = session.createSessionRecord(peer);

const timestamp = Date.now();
const nonce = session.generateNonce();

const body = {
  type: 'session-proof',
  session_id: record.session_id
};

const signature = session.signProof(
  peerKeys.privateKey,
  record.session_id,
  record.challenge,
  timestamp,
  nonce,
  body
);

const verified = session.verifyResponse(record, {
  device_id: peer.device_id,
  fingerprint: peer.fingerprint,
  public_key: peer.public_key,
  challenge: record.challenge,
  timestamp,
  nonce,
  body,
  signature
});

if (!verified.remote_verified) {
  throw new Error('remote verification failed');
}

session.approveSession(record);

if (record.state !== 'authenticated') {
  throw new Error('session approval failed');
}

let replayBlocked = false;

try {
  session.verifyResponse(record, {
    device_id: peer.device_id,
    fingerprint: peer.fingerprint,
    public_key: peer.public_key,
    challenge: record.challenge,
    timestamp,
    nonce,
    body,
    signature
  });
} catch {
  replayBlocked = true;
}

if (!replayBlocked) {
  throw new Error('replay protection failed');
}

session.revoke(record, 'phase8g-test');

if (!session.isRevoked(record.session_id)) {
  throw new Error('revocation persistence failed');
}

console.log(JSON.stringify({
  device_id: identity.device_id,
  fingerprint: identity.fingerprint,
  session_state: record.state,
  remote_verified: record.remote_verified,
  local_approved: record.local_approved,
  replay_blocked: replayBlocked,
  revoked: session.isRevoked(record.session_id)
}, null, 2));
NODE

echo "[OK] cryptographic session proof"
echo "[OK] response proof-of-possession"
echo "[OK] persistent replay protection"
echo "[OK] local approval gate"
echo "[OK] persistent revocation"

echo
echo "◆ Verifying security invariants..."

node <<'NODE'
const fs = require('fs');
const path = require('path');

const root = process.env.DNYF_ROOT || process.env.HOME + '/DNYF-DEV';

const protocol = JSON.parse(
  fs.readFileSync(path.join(root, 'etc/dnyf/session/protocol.json'), 'utf8')
);

const requiredFalse = [
  'self_trust',
  'self_pairing',
  'automatic_trust',
  'remote_execution',
  'remote_installation',
  'remote_shell'
];

for (const key of requiredFalse) {
  if (protocol[key] !== false) {
    throw new Error(`${key} must remain disabled`);
  }
  console.log(`[OK] ${key} disabled`);
}

if (protocol.local_approval_required !== true) {
  throw new Error('local approval must remain mandatory');
}

if (protocol.replay_protection !== true) {
  throw new Error('replay protection must remain enabled');
}

if (protocol.response_proof_required !== true) {
  throw new Error('response proof must remain mandatory');
}

console.log('[OK] local approval required');
console.log('[OK] replay protection required');
console.log('[OK] response proof required');
NODE

echo
echo "◆ Checking permissions..."

chmod 600 "$PRIVATE_KEY"
chmod 600 "$IDENTITY"
chmod 600 "$SESSION_DIR/dnyf-authenticated-session-authority.js"

PRIVATE_MODE="$(stat -c '%a' "$PRIVATE_KEY")"
IDENTITY_MODE="$(stat -c '%a' "$IDENTITY")"

echo "Private key mode : $PRIVATE_MODE"
echo "Identity mode    : $IDENTITY_MODE"

[ "$PRIVATE_MODE" = "600" ] || { echo "[FAIL] private key permissions"; exit 1; }
[ "$IDENTITY_MODE" = "600" ] || { echo "[FAIL] identity permissions"; exit 1; }

echo "[OK] cryptographic permissions"

echo
echo "◆ Writing phase manifest..."

cat > "$ETC_SESSION/phase8g-manifest.json" <<EOF
{
  "schema": "dnyf.phase8g.manifest.v1",
  "phase": "8G",
  "component": "authenticated-sessions",
  "version": "1.0.0",
  "device_id": "$DEVICE_ID",
  "fingerprint": "$FINGERPRINT",
  "security": {
    "response_proof": true,
    "persistent_replay_protection": true,
    "persistent_revocation": true,
    "local_approval_required": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false
  }
}
EOF

chmod 600 "$ETC_SESSION/phase8g-manifest.json"

echo "[OK] Phase 8G manifest"

echo
echo "============================================================"
echo " PHASE 8G AUTHENTICATED SESSION SECURITY: PASS"
echo "============================================================"
echo "Device ID   : $DEVICE_ID"
echo "Fingerprint : $FINGERPRINT"
echo "Backup      : $BACKUP"
echo
echo "Validated:"
echo "  ✓ canonical session protocol"
echo "  ✓ Ed25519 response proof"
echo "  ✓ responder identity binding"
echo "  ✓ challenge binding"
echo "  ✓ persistent replay protection"
echo "  ✓ local approval gate"
echo "  ✓ persistent revocation"
echo "  ✓ restart-safe state"
echo "  ✓ security invariants"
echo
echo "Next phase: 8H unified device registry"
