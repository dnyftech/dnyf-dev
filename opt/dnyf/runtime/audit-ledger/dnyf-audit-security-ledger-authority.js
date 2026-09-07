'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ENV_ROOT = process.env.DNYF_ROOT;
const LOCAL_ROOT = path.resolve(__dirname, '../../../..');
const ROOT =
  ENV_ROOT && ENV_ROOT.endsWith('/DNYF-DEV')
    ? ENV_ROOT
    : LOCAL_ROOT;

const ETC = path.join(ROOT, 'etc/dnyf/audit-ledger');
const STATE = path.join(ROOT, 'opt/dnyf/state/audit-ledger');
const LEDGER_DIR = path.join(STATE, 'ledger');
const AUDIT_DIR = path.join(STATE, 'audit');
const ANCHOR_DIR = path.join(STATE, 'anchors');

const SCHEMA_FILE = path.join(ETC, 'dnyf-audit-security-ledger-schema.json');
const POLICY_FILE = path.join(ETC, 'dnyf-audit-security-ledger-policy.json');

const IDENTITY_DIR = path.join(ROOT, 'opt/dnyf/runtime/secure/identity');
const IDENTITY_FILE = path.join(IDENTITY_DIR, 'identity.json');
const PRIVATE_KEY_FILE = path.join(IDENTITY_DIR, 'device-ed25519-private.pem');
const PUBLIC_KEY_FILE = path.join(IDENTITY_DIR, 'device-ed25519-public.pem');

const LEDGER_FILE = path.join(LEDGER_DIR, 'dnyf-security-audit-ledger.jsonl');
const STATE_FILE = path.join(STATE, 'local-audit-ledger-state.json');

function ensureDirs() {
  for (const d of [ETC, STATE, LEDGER_DIR, AUDIT_DIR, ANCHOR_DIR]) {
    fs.mkdirSync(d, { recursive: true });
  }
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function canonical(value) {
  if (Array.isArray(value)) {
    return value.map(canonical);
  }

  if (value && typeof value === 'object') {
    return Object.keys(value)
      .sort()
      .reduce((out, key) => {
        out[key] = canonical(value[key]);
        return out;
      }, {});
  }

  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonical(value));
}

function sha256(value) {
  return crypto
    .createHash('sha256')
    .update(typeof value === 'string' ? value : canonicalJson(value))
    .digest('hex');
}

function loadIdentity() {
  const identity = readJson(IDENTITY_FILE);

  const deviceId =
    identity.device_id ||
    (identity.identity && identity.identity.device_id);

  if (!deviceId) {
    throw new Error('canonical device identity missing');
  }

  return {
    device_id: deviceId,
    fingerprint:
      identity.fingerprint ||
      (identity.identity && identity.identity.fingerprint) ||
      null
  };
}

function loadSchema() {
  return readJson(SCHEMA_FILE);
}

function loadPolicy() {
  return readJson(POLICY_FILE);
}

function loadState() {
  ensureDirs();

  if (!fs.existsSync(STATE_FILE)) {
    const state = {
      schema: 'dnyf.audit.security.ledger.state.v1',
      ledger_sequence: 0,
      last_hash: 'GENESIS',
      last_record_id: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    fs.writeFileSync(
      STATE_FILE,
      JSON.stringify(state, null, 2) + '\n',
      { mode: 0o600 }
    );

    return state;
  }

  return readJson(STATE_FILE);
}

function saveState(state) {
  state.updated_at = new Date().toISOString();

  const temporary = STATE_FILE + '.tmp';
  fs.writeFileSync(
    temporary,
    JSON.stringify(state, null, 2) + '\n',
    { mode: 0o600 }
  );
  fs.renameSync(temporary, STATE_FILE);
  fs.chmodSync(STATE_FILE, 0o600);
}

function readRecords() {
  ensureDirs();

  if (!fs.existsSync(LEDGER_FILE)) {
    return [];
  }

  const raw = fs.readFileSync(LEDGER_FILE, 'utf8');

  if (!raw.trim()) {
    return [];
  }

  return raw
    .split('\n')
    .filter(Boolean)
    .map((line, index) => {
      try {
        return JSON.parse(line);
      } catch (error) {
        throw new Error(`invalid ledger JSON at line ${index + 1}`);
      }
    });
}

function buildUnsignedRecord(input, sequence, previousHash, identity) {
  const timestamp = input.timestamp || new Date().toISOString();

  const correlation = input.correlation || {};

  const payload =
    input.payload === undefined
      ? {}
      : input.payload;

  return {
    schema: 'dnyf.audit.security.record.v1',
    ledger: 'dnyf-audit-ledger/1',
    ledger_sequence: sequence,
    record_id: crypto.randomUUID(),
    timestamp,
    event_type: String(input.event_type || 'dnyf.audit.security.record'),
    severity: String(input.severity || 'info'),
    source: String(input.source || 'dnyf'),
    device_id: identity.device_id,
    service: String(input.service || 'dnyf-audit-ledger'),
    correlation: {
      policy_decision_id:
        correlation.policy_decision_id || null,
      event_id:
        correlation.event_id || null,
      session_id:
        correlation.session_id || null,
      request_id:
        correlation.request_id || null,
      task_id:
        correlation.task_id || null
    },
    payload,
    previous_hash: previousHash
  };
}

function signRecord(unsignedRecord) {
  const unsignedCanonical = canonicalJson(unsignedRecord);
  const recordHash = sha256(unsignedCanonical);

  const signature = crypto.sign(
    null,
    Buffer.from(unsignedCanonical, 'utf8'),
    fs.readFileSync(PRIVATE_KEY_FILE)
  ).toString('base64');

  return {
    ...unsignedRecord,
    record_hash: recordHash,
    signature
  };
}

function verifyRecord(record) {
  if (!record || typeof record !== 'object') {
    return { ok: false, reason: 'invalid-record' };
  }

  const signature = record.signature;
  const recordHash = record.record_hash;

  if (!signature || !recordHash) {
    return { ok: false, reason: 'missing-integrity-fields' };
  }

  const unsigned = { ...record };
  delete unsigned.record_hash;
  delete unsigned.signature;

  const canonicalUnsigned = canonicalJson(unsigned);
  const expectedHash = sha256(canonicalUnsigned);

  if (expectedHash !== recordHash) {
    return {
      ok: false,
      reason: 'record-hash-mismatch',
      expected: expectedHash,
      actual: recordHash
    };
  }

  const verified = crypto.verify(
    null,
    Buffer.from(canonicalUnsigned, 'utf8'),
    fs.readFileSync(PUBLIC_KEY_FILE),
    Buffer.from(signature, 'base64')
  );

  if (!verified) {
    return {
      ok: false,
      reason: 'signature-invalid'
    };
  }

  return {
    ok: true,
    record_hash: recordHash
  };
}

function validateInput(input) {
  const policy = loadPolicy();

  if (!input || typeof input !== 'object') {
    throw new Error('audit record must be an object');
  }

  if (!input.event_type) {
    throw new Error('event_type required');
  }

  const severity = input.severity || 'info';

  if (!policy.allowed_severity.includes(severity)) {
    throw new Error('severity-not-allowed');
  }

  const forbiddenTypes = [
    'dnyf.trust.auto',
    'dnyf.pair.auto',
    'dnyf.exec.remote',
    'dnyf.install.remote',
    'dnyf.shell.remote',
    'dnyf.privilege.escalation'
  ];

  if (
    forbiddenTypes.some(
      prefix => String(input.event_type).startsWith(prefix)
    )
  ) {
    throw new Error('forbidden-security-operation');
  }

  return true;
}

function append(input, authorization = {}) {
  ensureDirs();

  validateInput(input);

  const identity = loadIdentity();

  if (authorization.authority !== 'local-audit-authority') {
    throw new Error('unauthorized-append');
  }

  if (authorization.device_id !== identity.device_id) {
    throw new Error('identity-binding-failed');
  }

  const state = loadState();
  const records = readRecords();

  if (records.length > 0) {
    const last = records[records.length - 1];

    if (last.ledger_sequence !== state.ledger_sequence) {
      throw new Error('ledger-state-sequence-mismatch');
    }

    if (last.record_hash !== state.last_hash) {
      throw new Error('ledger-state-hash-mismatch');
    }
  }

  const sequence = state.ledger_sequence + 1;
  const previousHash = state.last_hash;

  const unsigned = buildUnsignedRecord(
    input,
    sequence,
    previousHash,
    identity
  );

  const record = signRecord(unsigned);

  const integrity = verifyRecord(record);

  if (!integrity.ok) {
    throw new Error(`self-verification-failed:${integrity.reason}`);
  }

  if (records.some(
    existing => existing.ledger_sequence === sequence
  )) {
    throw new Error('duplicate-sequence');
  }

  fs.appendFileSync(
    LEDGER_FILE,
    JSON.stringify(record) + '\n',
    { mode: 0o600 }
  );

  fs.chmodSync(LEDGER_FILE, 0o600);

  state.ledger_sequence = sequence;
  state.last_hash = record.record_hash;
  state.last_record_id = record.record_id;

  saveState(state);

  const auditFile = path.join(
    AUDIT_DIR,
    `record-${String(sequence).padStart(12, '0')}.json`
  );

  fs.writeFileSync(
    auditFile,
    JSON.stringify(record, null, 2) + '\n',
    { mode: 0o600 }
  );

  return record;
}

function verifyChain() {
  ensureDirs();

  const records = readRecords();

  let previousHash = 'GENESIS';
  let expectedSequence = 1;

  for (const record of records) {
    if (record.ledger_sequence !== expectedSequence) {
      return {
        ok: false,
        reason: 'sequence-integrity-failure',
        expected_sequence: expectedSequence,
        actual_sequence: record.ledger_sequence
      };
    }

    if (record.previous_hash !== previousHash) {
      return {
        ok: false,
        reason: 'chain-integrity-failure',
        sequence: record.ledger_sequence
      };
    }

    const result = verifyRecord(record);

    if (!result.ok) {
      return {
        ok: false,
        reason: result.reason,
        sequence: record.ledger_sequence
      };
    }

    previousHash = record.record_hash;
    expectedSequence += 1;
  }

  const state = loadState();

  if (records.length === 0) {
    if (
      state.ledger_sequence !== 0 ||
      state.last_hash !== 'GENESIS'
    ) {
      return {
        ok: false,
        reason: 'empty-ledger-state-mismatch'
      };
    }
  } else {
    const last = records[records.length - 1];

    if (state.ledger_sequence !== last.ledger_sequence) {
      return {
        ok: false,
        reason: 'state-sequence-mismatch'
      };
    }

    if (state.last_hash !== last.record_hash) {
      return {
        ok: false,
        reason: 'state-hash-mismatch'
      };
    }
  }

  return {
    ok: true,
    records: records.length,
    last_sequence: records.length,
    last_hash: previousHash
  };
}

function fingerprint() {
  return sha256(
    canonicalJson({
      schema: loadSchema(),
      policy: loadPolicy()
    })
  );
}

function status() {
  const identity = loadIdentity();
  const state = loadState();
  const records = readRecords();
  const verification = verifyChain();

  return {
    schema: 'dnyf.audit.security.ledger.status.v1',
    service: 'dnyf-audit-ledger',
    device_id: identity.device_id,
    fingerprint: identity.fingerprint,
    protocol: 'dnyf-audit-ledger/1',
    version: '1.0.0',
    ledger_file: LEDGER_FILE,
    ledger_sequence: state.ledger_sequence,
    record_count: records.length,
    last_record_id: state.last_record_id,
    last_hash: state.last_hash,
    ledger_fingerprint: fingerprint(),
    integrity: verification,
    security: {
      append_only: true,
      signed_records: true,
      hash_chain: true,
      replay_sequence_protection: true,
      tamper_detection: true,
      normal_delete: false,
      trust_grant: false,
      authorization_grant: false,
      execution_grant: false,
      installation_grant: false,
      shell_grant: false,
      privilege_escalation: false,
      self_trust: false,
      self_pairing: false,
      automatic_trust: false
    }
  };
}

function findRecords(query) {
  const records = readRecords();

  if (!query) {
    return records;
  }

  const q = String(query).toLowerCase();

  return records.filter(record =>
    JSON.stringify(record).toLowerCase().includes(q)
  );
}

function tail(count = 10) {
  const records = readRecords();
  const n = Math.max(1, Number(count) || 10);
  return records.slice(-n);
}

function createArchiveAnchor() {
  const verification = verifyChain();

  if (!verification.ok) {
    throw new Error('cannot-anchor-invalid-ledger');
  }

  const state = loadState();

  const anchor = {
    schema: 'dnyf.audit.ledger.anchor.v1',
    protocol: 'dnyf-audit-ledger/1',
    created_at: new Date().toISOString(),
    device_id: loadIdentity().device_id,
    ledger_sequence: state.ledger_sequence,
    last_hash: state.last_hash,
    ledger_fingerprint: fingerprint()
  };

  const anchorHash = sha256(anchor);

  const signature = crypto.sign(
    null,
    Buffer.from(canonicalJson(anchor), 'utf8'),
    fs.readFileSync(PRIVATE_KEY_FILE)
  ).toString('base64');

  const finalAnchor = {
    ...anchor,
    anchor_hash: anchorHash,
    signature
  };

  const file = path.join(
    ANCHOR_DIR,
    `ledger-anchor-${state.ledger_sequence}.json`
  );

  fs.writeFileSync(
    file,
    JSON.stringify(finalAnchor, null, 2) + '\n',
    { mode: 0o600 }
  );

  return finalAnchor;
}

module.exports = {
  ROOT,
  LEDGER_FILE,
  STATE_FILE,
  canonical,
  canonicalJson,
  sha256,
  loadIdentity,
  loadSchema,
  loadPolicy,
  loadState,
  readRecords,
  append,
  verifyRecord,
  verifyChain,
  fingerprint,
  status,
  findRecords,
  tail,
  createArchiveAnchor
};
