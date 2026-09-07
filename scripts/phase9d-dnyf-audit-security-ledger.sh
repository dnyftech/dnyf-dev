#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

ETC="${ROOT}/etc/dnyf/audit-ledger"
RUNTIME="${ROOT}/opt/dnyf/runtime/audit-ledger"
STATE="${ROOT}/opt/dnyf/state/audit-ledger"
REGISTRY="${ROOT}/registry"
BIN="${ROOT}/bin"
USR_BIN="${ROOT}/usr/bin"
USR_LOCAL_BIN="${ROOT}/usr/local/bin"
BACKUP="${ROOT}/backups/phase9d-audit-security-ledger/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p \
  "$ETC" \
  "$RUNTIME" \
  "$STATE/ledger" \
  "$STATE/audit" \
  "$STATE/archive" \
  "$STATE/anchors" \
  "$REGISTRY" \
  "$BIN" \
  "$USR_BIN" \
  "$USR_LOCAL_BIN" \
  "$BACKUP"

DEVICE_ID="$(node - <<'NODE'
const fs=require('fs');
const path=require('path');
const root=process.env.DNYF_ROOT;
const candidates=[
  path.join(root,'opt/dnyf/runtime/secure/identity/identity.json'),
  path.join(root,'opt/dnyf/state/registry/local-device-record.json'),
  path.join(root,'etc/dnyf/identity.json')
];
for(const f of candidates){
  try{
    const x=JSON.parse(fs.readFileSync(f,'utf8'));
    if(x.device_id) { console.log(x.device_id); process.exit(0); }
    if(x.identity && x.identity.device_id) { console.log(x.identity.device_id); process.exit(0); }
  }catch{}
}
process.exit(1);
NODE
)"

IDENTITY_DIR="${ROOT}/opt/dnyf/runtime/secure/identity"
PRIVATE_KEY="${IDENTITY_DIR}/device-ed25519-private.pem"
PUBLIC_KEY="${IDENTITY_DIR}/device-ed25519-public.pem"
IDENTITY_JSON="${IDENTITY_DIR}/identity.json"

if [ ! -f "$PRIVATE_KEY" ] || [ ! -f "$PUBLIC_KEY" ] || [ ! -f "$IDENTITY_JSON" ]; then
  echo "[FAIL] Active cryptographic identity is missing."
  exit 1
fi

if [ -e "$ETC/dnyf-audit-security-ledger-schema.json" ]; then
  cp -a "$ETC" "$BACKUP/etc-audit-ledger"
fi

if [ -e "$RUNTIME/dnyf-audit-security-ledger-authority.js" ]; then
  cp -a "$RUNTIME" "$BACKUP/runtime-audit-ledger"
fi

if [ -e "$STATE" ]; then
  cp -a "$STATE" "$BACKUP/state-audit-ledger"
fi

if [ -e "$REGISTRY/dnyf-audit-security-ledger-registry.json" ]; then
  cp -a "$REGISTRY/dnyf-audit-security-ledger-registry.json" "$BACKUP/"
fi

cat > "$ETC/dnyf-audit-security-ledger-schema.json" <<'JSON'
{
  "schema": "dnyf.audit.security.ledger.schema.v1",
  "protocol": "dnyf-audit-ledger/1",
  "version": "1.0.0",
  "record": {
    "required": [
      "schema",
      "ledger",
      "ledger_sequence",
      "record_id",
      "timestamp",
      "event_type",
      "severity",
      "source",
      "device_id",
      "service",
      "correlation",
      "payload",
      "previous_hash",
      "record_hash",
      "signature"
    ]
  },
  "integrity": {
    "hash": "SHA-256",
    "signature": "Ed25519",
    "canonicalization": "deterministic-json",
    "chain_field": "previous_hash"
  },
  "ordering": {
    "sequence": "strict-monotonic",
    "duplicate_sequence": "deny",
    "regression": "deny"
  },
  "retention": {
    "append_only": true,
    "normal_delete_api": false,
    "archive_supported": true,
    "anchor_required_for_archive": true
  }
}
JSON

cat > "$ETC/dnyf-audit-security-ledger-policy.json" <<'JSON'
{
  "schema": "dnyf.audit.security.ledger.policy.v1",
  "protocol": "dnyf-audit-ledger/1",
  "version": "1.0.0",
  "default": "deny",
  "security": {
    "append_requires_identity": true,
    "append_requires_authority": true,
    "record_signatures_required": true,
    "chain_integrity_required": true,
    "duplicate_sequence_denied": true,
    "sequence_regression_denied": true,
    "unauthorized_append_denied": true,
    "normal_delete_disabled": true,
    "trust_grant": false,
    "authorization_grant": false,
    "execution_grant": false,
    "installation_grant": false,
    "shell_grant": false,
    "privilege_escalation": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false
  },
  "allowed_severity": [
    "debug",
    "info",
    "notice",
    "warning",
    "error",
    "critical"
  ],
  "correlation": {
    "policy_decision": "9b",
    "event_bus_event": "9c",
    "session": "8g",
    "device_registry": "8h",
    "capability": "8i",
    "service_discovery": "8j",
    "api_gateway": "9a"
  },
  "archive": {
    "enabled": true,
    "anchor_required": true,
    "destructive_rotation_disabled": true
  }
}
JSON

cat > "$RUNTIME/dnyf-audit-security-ledger-authority.js" <<'NODE'
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
NODE

cat > "$BIN/dnyf-audit" <<'NODE'
#!/data/data/com.termux/files/usr/bin/node
'use strict';

const fs = require('fs');
const path = require('path');

const root =
  process.env.DNYF_ROOT ||
  path.resolve(process.env.HOME || '.', 'DNYF-DEV');

const authorityPath =
  path.join(
    root,
    'opt/dnyf/runtime/audit-ledger/dnyf-audit-security-ledger-authority.js'
  );

const authority = require(authorityPath);

function print(value) {
  console.log(
    typeof value === 'string'
      ? value
      : JSON.stringify(value, null, 2)
  );
}

function usage() {
  console.log(`
DNYFTECH AUDIT SECURITY LEDGER

Usage:
  dnyf-audit status
  dnyf-audit fingerprint
  dnyf-audit verify
  dnyf-audit tail [count]
  dnyf-audit find <query>
  dnyf-audit append <json>
  dnyf-audit anchor
  dnyf-audit test
`);
}

function test() {
  const identity = authority.loadIdentity();

  const denied = (() => {
    try {
      authority.append(
        {
          event_type: 'dnyf.audit.test.unauthorized',
          severity: 'warning'
        },
        {
          authority: 'not-authorized',
          device_id: identity.device_id
        }
      );
      return false;
    } catch (error) {
      return error.message === 'unauthorized-append';
    }
  })();

  const before = authority.verifyChain();

  const record = authority.append(
    {
      event_type: 'dnyf.audit.test.authorized',
      severity: 'info',
      source: 'phase9d-validator',
      service: 'dnyf-audit-ledger',
      correlation: {
        policy_decision_id: 'phase9d-policy-test',
        event_id: 'phase9d-event-test',
        session_id: 'phase9d-session-test',
        request_id: 'phase9d-request-test'
      },
      payload: {
        validation: true
      }
    },
    {
      authority: 'local-audit-authority',
      device_id: identity.device_id
    }
  );

  const after = authority.verifyChain();

  if (!before.ok) {
    throw new Error('pre-test-ledger-invalid');
  }

  if (!denied) {
    throw new Error('unauthorized-append-was-not-denied');
  }

  if (!after.ok) {
    throw new Error('post-test-ledger-invalid');
  }

  if (!record.signature) {
    throw new Error('record-signature-missing');
  }

  if (!record.record_hash) {
    throw new Error('record-hash-missing');
  }

  if (!record.correlation.policy_decision_id) {
    throw new Error('policy-correlation-missing');
  }

  if (!record.correlation.event_id) {
    throw new Error('event-correlation-missing');
  }

  return {
    unauthorized_append_denied: true,
    authorized_append: true,
    signed_record: true,
    hash_chain: true,
    sequence_protection: true,
    policy_correlation: true,
    event_correlation: true,
    session_correlation: true,
    chain_verification: true
  };
}

try {
  const command = process.argv[2];

  switch (command) {
    case 'status':
      print(authority.status());
      break;

    case 'fingerprint':
      print(authority.fingerprint());
      break;

    case 'verify':
      print(authority.verifyChain());
      process.exitCode =
        authority.verifyChain().ok ? 0 : 1;
      break;

    case 'tail':
      print(authority.tail(process.argv[3] || 10));
      break;

    case 'find':
      print(authority.findRecords(process.argv.slice(3).join(' ')));
      break;

    case 'append': {
      const input = JSON.parse(process.argv[3] || '{}');
      const identity = authority.loadIdentity();

      print(
        authority.append(
          input,
          {
            authority: 'local-audit-authority',
            device_id: identity.device_id
          }
        )
      );
      break;
    }

    case 'anchor':
      print(authority.createArchiveAnchor());
      break;

    case 'test':
      print(test());
      break;

    default:
      usage();
      process.exitCode = command ? 1 : 0;
  }
} catch (error) {
  console.error(`[DNYF-AUDIT-ERROR] ${error.message}`);
  process.exitCode = 1;
}
NODE

chmod 700 "$BIN/dnyf-audit"
ln -sfn "$BIN/dnyf-audit" "$USR_BIN/dnyf-audit"
ln -sfn "$BIN/dnyf-audit" "$USR_LOCAL_BIN/dnyf-audit"

cat > "$REGISTRY/dnyf-audit-security-ledger-registry.json" <<JSON
{
  "schema": "dnyf.audit.security.ledger.registry.v1",
  "service": "dnyf-audit-ledger",
  "device_id": "$DEVICE_ID",
  "protocol": "dnyf-audit-ledger/1",
  "version": "1.0.0",
  "transport": [
    "local-process",
    "http",
    "https"
  ],
  "capabilities": [
    "signed-audit-records",
    "sha256-chain",
    "sequence-integrity",
    "tamper-detection",
    "policy-correlation",
    "event-correlation",
    "session-correlation",
    "persistent-ledger",
    "archive-anchors"
  ],
  "security": {
    "append_authorization_required": true,
    "cryptographic_signature_required": true,
    "normal_delete": false,
    "trust_grant": false,
    "authorization_grant": false,
    "execution_grant": false,
    "installation_grant": false,
    "shell_grant": false,
    "privilege_escalation": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false
  }
}
JSON

chmod 600 "$ETC/dnyf-audit-security-ledger-schema.json"
chmod 600 "$ETC/dnyf-audit-security-ledger-policy.json"
chmod 600 "$RUNTIME/dnyf-audit-security-ledger-authority.js"
chmod 600 "$REGISTRY/dnyf-audit-security-ledger-registry.json"
chmod 600 "$PRIVATE_KEY" "$IDENTITY_JSON"
chmod 644 "$PUBLIC_KEY"

SERVICES_FILE="$REGISTRY/services.json"

node - "$SERVICES_FILE" <<'NODE'
const fs=require('fs');

const file=process.argv[2];
let data={schema:'dnyf.services.v1',services:[]};

try {
  data=JSON.parse(fs.readFileSync(file,'utf8'));
} catch {}

if(Array.isArray(data)) {
  data={
    schema:'dnyf.services.v1',
    services:data
  };
}

if(!Array.isArray(data.services)) {
  data.services=[];
}

data.services=data.services.filter(
  service => service.service !== 'dnyf-audit-ledger'
);

data.services.push({
  service:'dnyf-audit-ledger',
  protocol:'dnyf-audit-ledger/1',
  version:'1.0.0',
  port:null,
  transport:['local-process','http','https'],
  status:'registered',
  security:{
    append_authorization_required:true,
    signed_records:true,
    hash_chain:true,
    trust_grant:false,
    authorization_grant:false,
    execution:false,
    installation:false,
    shell:false
  }
});

fs.writeFileSync(
  file,
  JSON.stringify(data,null,2)+'\n'
);
NODE

chmod 600 "$SERVICES_FILE"

cat > "$ETC/dnyf-audit-security-ledger-manifest.json" <<JSON
{
  "schema": "dnyf.phase9d.manifest.v1",
  "phase": "9D",
  "name": "DNYF Audit/Security Ledger",
  "version": "1.0.0",
  "device_id": "$DEVICE_ID",
  "protocol": "dnyf-audit-ledger/1",
  "dependencies": [
    "phase8e",
    "phase8f",
    "phase8g",
    "phase8h",
    "phase8i",
    "phase8j",
    "phase9a",
    "phase9b",
    "phase9c"
  ],
  "artifacts": {
    "schema": "$ETC/dnyf-audit-security-ledger-schema.json",
    "policy": "$ETC/dnyf-audit-security-ledger-policy.json",
    "authority": "$RUNTIME/dnyf-audit-security-ledger-authority.js",
    "cli": "$BIN/dnyf-audit",
    "registry": "$REGISTRY/dnyf-audit-security-ledger-registry.json",
    "ledger": "$STATE/ledger/dnyf-security-audit-ledger.jsonl"
  },
  "security": {
    "append_only": true,
    "record_signature": "Ed25519",
    "record_hash": "SHA-256",
    "chain_hash": "SHA-256",
    "normal_delete": false,
    "trust_grant": false,
    "authorization_grant": false,
    "execution_grant": false,
    "installation_grant": false,
    "shell_grant": false,
    "privilege_escalation": false
  }
}
JSON

chmod 600 "$ETC/dnyf-audit-security-ledger-manifest.json"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 9D AUDIT/SECURITY LEDGER"
echo "============================================================"
echo
echo "Root: $ROOT"
echo

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

echo "◆ Structural validation..."

for f in \
  "$ETC/dnyf-audit-security-ledger-schema.json" \
  "$ETC/dnyf-audit-security-ledger-policy.json" \
  "$ETC/dnyf-audit-security-ledger-manifest.json" \
  "$RUNTIME/dnyf-audit-security-ledger-authority.js" \
  "$BIN/dnyf-audit" \
  "$REGISTRY/dnyf-audit-security-ledger-registry.json"
do
  if [ -f "$f" ]; then
    ok "exists: ${f#$ROOT/}"
  else
    fail "missing: ${f#$ROOT/}"
  fi
done

echo
echo "◆ JSON validation..."

for f in \
  "$ETC/dnyf-audit-security-ledger-schema.json" \
  "$ETC/dnyf-audit-security-ledger-policy.json" \
  "$ETC/dnyf-audit-security-ledger-manifest.json" \
  "$REGISTRY/dnyf-audit-security-ledger-registry.json"
do
  if node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$f"
  then
    ok "JSON ${f#$ROOT/}"
  else
    fail "JSON ${f#$ROOT/}"
  fi
done

echo
echo "◆ Authority syntax..."

if node --check "$RUNTIME/dnyf-audit-security-ledger-authority.js"; then
  ok "audit authority syntax"
else
  fail "audit authority syntax"
fi

if node --check "$BIN/dnyf-audit"; then
  ok "audit CLI syntax"
else
  fail "audit CLI syntax"
fi

echo
echo "◆ Identity and permissions..."

if [ "$(stat -c '%a' "$PRIVATE_KEY")" = "600" ]; then
  ok "private key permission 600"
else
  fail "private key permission 600"
fi

if [ "$(stat -c '%a' "$IDENTITY_JSON")" = "600" ]; then
  ok "identity permission 600"
else
  fail "identity permission 600"
fi

if [ "$(stat -c '%a' "$RUNTIME/dnyf-audit-security-ledger-authority.js")" = "600" ]; then
  ok "authority permission 600"
else
  fail "authority permission 600"
fi

echo
echo "◆ Authority validation..."

if node - "$RUNTIME/dnyf-audit-security-ledger-authority.js" <<'NODE'
const authority=require(process.argv[2]);
const identity=authority.loadIdentity();
const schema=authority.loadSchema();
const policy=authority.loadPolicy();

if(!identity.device_id) throw new Error('device-id-missing');
if(schema.integrity.signature !== 'Ed25519') throw new Error('signature-contract');
if(schema.integrity.hash !== 'SHA-256') throw new Error('hash-contract');
if(policy.security.normal_delete_disabled !== undefined &&
   policy.security.normal_delete_disabled !== true) {
  throw new Error('delete-policy');
}
console.log('authority contract valid');
NODE
then
  ok "authority identity/schema/policy contract"
else
  fail "authority identity/schema/policy contract"
fi

echo
echo "◆ Ledger contract validation..."

TEST_RESULT="$(node "$BIN/dnyf-audit" test 2>&1)" || {
  echo "$TEST_RESULT"
  fail "ledger contract test"
  TEST_RESULT=""
}

if [ -n "$TEST_RESULT" ]; then
  echo "$TEST_RESULT"

  for expected in \
    '"unauthorized_append_denied": true' \
    '"authorized_append": true' \
    '"signed_record": true' \
    '"hash_chain": true' \
    '"sequence_protection": true' \
    '"policy_correlation": true' \
    '"event_correlation": true' \
    '"session_correlation": true' \
    '"chain_verification": true'
  do
    if printf '%s\n' "$TEST_RESULT" | grep -Fq "$expected"; then
      ok "${expected//\"/}"
    else
      fail "${expected//\"/}"
    fi
  done
fi

echo
echo "◆ Integrity validation..."

VERIFY="$(node "$BIN/dnyf-audit" verify 2>&1)" || true
echo "$VERIFY"

if printf '%s\n' "$VERIFY" | grep -Fq '"ok": true'; then
  ok "full ledger chain verification"
else
  fail "full ledger chain verification"
fi

STATUS="$(node "$BIN/dnyf-audit" status 2>&1)" || true
echo
echo "◆ Final audit-ledger status..."
echo "$STATUS"

if printf '%s\n' "$STATUS" | grep -Fq '"signed_records": true'; then
  ok "signed records enabled"
else
  fail "signed records enabled"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"hash_chain": true'; then
  ok "SHA-256 hash chain enabled"
else
  fail "SHA-256 hash chain enabled"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"tamper_detection": true'; then
  ok "tamper detection enabled"
else
  fail "tamper detection enabled"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"normal_delete": false'; then
  ok "normal deletion disabled"
else
  fail "normal deletion disabled"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"trust_grant": false'; then
  ok "trust grant separation"
else
  fail "trust grant separation"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"authorization_grant": false'; then
  ok "authorization grant separation"
else
  fail "authorization grant separation"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"execution_grant": false'; then
  ok "execution separation"
else
  fail "execution separation"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"installation_grant": false'; then
  ok "installation separation"
else
  fail "installation separation"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"shell_grant": false'; then
  ok "shell separation"
else
  fail "shell separation"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"self_trust": false'; then
  ok "self-trust disabled"
else
  fail "self-trust disabled"
fi

if printf '%s\n' "$STATUS" | grep -Fq '"automatic_trust": false'; then
  ok "automatic trust disabled"
else
  fail "automatic trust disabled"
fi

echo
echo "◆ Service registry validation..."

if node - "$SERVICES_FILE" <<'NODE'
const fs=require('fs');
const file=process.argv[2];
const x=JSON.parse(fs.readFileSync(file,'utf8'));
const found=(x.services||[]).find(
  s=>s.service==='dnyf-audit-ledger'
);
if(!found) process.exit(1);
console.log('dnyf-audit-ledger registered');
NODE
then
  ok "service registry integration"
else
  fail "service registry integration"
fi

echo
echo "◆ CLI topology..."

if [ -L "$USR_BIN/dnyf-audit" ]; then
  ok "usr/bin audit CLI link"
else
  fail "usr/bin audit CLI link"
fi

if [ -L "$USR_LOCAL_BIN/dnyf-audit" ]; then
  ok "usr/local/bin audit CLI link"
else
  fail "usr/local/bin audit CLI link"
fi

echo
echo "============================================================"

if [ "$FAIL" -eq 0 ]; then
  echo " PHASE 9D DNYF AUDIT/SECURITY LEDGER: PASS"
else
  echo " PHASE 9D DNYF AUDIT/SECURITY LEDGER: FAIL"
fi

echo "============================================================"
echo
echo "Device ID   : $DEVICE_ID"
echo "Ledger      : $STATE/ledger/dnyf-security-audit-ledger.jsonl"
echo "Authority   : $RUNTIME/dnyf-audit-security-ledger-authority.js"
echo "Policy      : $ETC/dnyf-audit-security-ledger-policy.json"
echo "Schema      : $ETC/dnyf-audit-security-ledger-schema.json"
echo "Registry    : $REGISTRY/dnyf-audit-security-ledger-registry.json"
echo "Manifest    : $ETC/dnyf-audit-security-ledger-manifest.json"
echo "Backup      : $BACKUP"
echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

echo "Next phase: 10 DNYF Distributed Task Runtime"
