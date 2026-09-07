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
