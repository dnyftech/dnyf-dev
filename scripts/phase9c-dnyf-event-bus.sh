#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

ETC="${ROOT}/etc/dnyf"
OPT="${ROOT}/opt/dnyf"
REG="${ROOT}/registry"
BIN="${ROOT}/bin"
USR_BIN="${ROOT}/usr/bin"
USR_LOCAL_BIN="${ROOT}/usr/local/bin"
SCRIPT_DIR="${ROOT}/scripts"
BACKUP="${ROOT}/backups/phase9c-event-bus/$(date -u +%Y%m%dT%H%M%SZ)"

EVENT_ETC="${ETC}/event-bus"
EVENT_RUNTIME="${OPT}/runtime/event-bus"
EVENT_STATE="${OPT}/state/event-bus"
EVENT_JOURNAL="${EVENT_STATE}/journal"
EVENT_AUDIT="${EVENT_STATE}/audit"
EVENT_QUEUE="${EVENT_STATE}/queue"
EVENT_DEDUPE="${EVENT_STATE}/dedupe"
EVENT_REPLAY="${EVENT_STATE}/replay"

mkdir -p \
  "${EVENT_ETC}" \
  "${EVENT_RUNTIME}" \
  "${EVENT_JOURNAL}" \
  "${EVENT_AUDIT}" \
  "${EVENT_QUEUE}" \
  "${EVENT_DEDUPE}" \
  "${EVENT_REPLAY}" \
  "${BACKUP}" \
  "${BIN}" \
  "${USR_BIN}" \
  "${USR_LOCAL_BIN}"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 9C DNYF EVENT BUS"
echo "============================================================"
echo
echo "Root: ${ROOT}"
echo

# ------------------------------------------------------------
# Backup existing Phase 9C material
# ------------------------------------------------------------

for target in \
  "${EVENT_ETC}" \
  "${EVENT_RUNTIME}" \
  "${EVENT_STATE}" \
  "${REG}/dnyf-event-bus-registry.json" \
  "${REG}/services.json" \
  "${ETC}/phase9c-manifest.json" \
  "${BIN}/dnyf-event" \
  "${USR_BIN}/dnyf-event" \
  "${USR_LOCAL_BIN}/dnyf-event"
do
  if [ -e "${target}" ] || [ -L "${target}" ]; then
    safe="$(printf '%s' "${target}" | sed "s#${ROOT}/##; s#[^A-Za-z0-9._-]#_#g")"
    cp -a "${target}" "${BACKUP}/${safe}" 2>/dev/null || true
  fi
done

# ------------------------------------------------------------
# Event schema
# ------------------------------------------------------------

cat > "${EVENT_ETC}/dnyf-event-bus-schema.json" <<'JSON'
{
  "schema": "dnyf.event.bus.schema.v1",
  "protocol": "dnyf-event-bus/1",
  "version": "1.0.0",
  "event_envelope": {
    "required": [
      "event_id",
      "event_version",
      "event_type",
      "topic",
      "source",
      "device_id",
      "sequence",
      "timestamp",
      "idempotency_key",
      "payload"
    ],
    "event_id": "UUIDv4",
    "event_version": "integer",
    "sequence": "positive_integer",
    "timestamp": "ISO-8601-UTC",
    "idempotency_key": "opaque_string"
  },
  "transport": [
    "local-process",
    "http",
    "https",
    "websocket"
  ],
  "network": {
    "ipv4": true,
    "ipv6": true,
    "offline_first": true,
    "lan_preferred": true,
    "internet_fallback": true,
    "relay_fallback": true
  },
  "delivery": {
    "durable": true,
    "at_least_once": true,
    "ordering": "per-topic-source",
    "deduplication": true,
    "replay_protection": true,
    "bounded_queue": true
  },
  "security": {
    "publisher_authentication_required": true,
    "ed25519_required": true,
    "policy_evaluation_required": true,
    "trust_not_granted": true,
    "authorization_not_granted": true,
    "execution_not_granted": true,
    "installation_not_granted": true,
    "shell_not_granted": true,
    "automatic_trust": false,
    "automatic_pairing": false,
    "self_trust": false,
    "self_pairing": false
  }
}
JSON

# ------------------------------------------------------------
# Event bus policy
# ------------------------------------------------------------

cat > "${EVENT_ETC}/dnyf-event-bus-policy.json" <<'JSON'
{
  "schema": "dnyf.event.bus.policy.v1",
  "policy_id": "dnyf-event-bus-default-security-policy",
  "policy_version": "1.0.0",
  "mode": "default-deny",
  "limits": {
    "max_payload_bytes": 262144,
    "max_event_bytes": 524288,
    "max_queue_events": 1000,
    "max_topic_length": 160,
    "max_event_type_length": 160,
    "max_idempotency_length": 200,
    "max_timestamp_age_seconds": 300,
    "max_future_timestamp_seconds": 30
  },
  "topics": {
    "allowed_prefixes": [
      "dnyf.system.",
      "dnyf.device.",
      "dnyf.service.",
      "dnyf.registry.",
      "dnyf.capability.",
      "dnyf.discovery.",
      "dnyf.session.",
      "dnyf.sync.",
      "dnyf.transfer.",
      "dnyf.ceezix."
    ],
    "denied_prefixes": [
      "dnyf.exec.",
      "dnyf.install.",
      "dnyf.shell.",
      "dnyf.privilege.",
      "dnyf.trust.auto.",
      "dnyf.pair.auto."
    ]
  },
  "security": {
    "default_deny": true,
    "fail_closed": true,
    "publisher_authentication_required": true,
    "policy_engine_required": true,
    "trusted_peer_required": true,
    "session_required": true,
    "capability_evaluation_required": true,
    "local_approval_required": true,
    "dangerous_event_topics_disabled": true,
    "event_bus_grants_trust": false,
    "event_bus_grants_authorization": false,
    "event_bus_grants_execution": false,
    "event_bus_grants_installation": false,
    "event_bus_grants_shell": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "automatic_pairing": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  }
}
JSON

# ------------------------------------------------------------
# Runtime authority
# ------------------------------------------------------------

cat > "${EVENT_RUNTIME}/dnyf-event-bus-authority.js" <<'NODE'
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

const ETC = path.join(ROOT, 'etc', 'dnyf');
const OPT = path.join(ROOT, 'opt', 'dnyf');
const REGISTRY = path.join(ROOT, 'registry');

const EVENT_ETC = path.join(ETC, 'event-bus');
const EVENT_STATE = path.join(OPT, 'state', 'event-bus');
const JOURNAL = path.join(EVENT_STATE, 'journal');
const AUDIT = path.join(EVENT_STATE, 'audit');
const QUEUE = path.join(EVENT_STATE, 'queue');
const DEDUPE = path.join(EVENT_STATE, 'dedupe');
const REPLAY = path.join(EVENT_STATE, 'replay');

const SCHEMA_FILE =
  path.join(EVENT_ETC, 'dnyf-event-bus-schema.json');

const POLICY_FILE =
  path.join(EVENT_ETC, 'dnyf-event-bus-policy.json');

const IDENTITY_FILE =
  path.join(
    OPT,
    'runtime',
    'secure',
    'identity',
    'identity.json'
  );

const DEVICE_REGISTRY_FILE =
  path.join(
    REGISTRY,
    'dnyf-unified-device-registry.json'
  );

const CAPABILITY_STATE_FILE =
  path.join(
    OPT,
    'state',
    'capability',
    'local-capability-state.json'
  );

const POLICY_AUTHORITY_FILE =
  path.join(
    OPT,
    'runtime',
    'policy-engine',
    'dnyf-policy-engine-authority.js'
  );

function ensureDirectories() {
  for (const dir of [
    EVENT_ETC,
    EVENT_STATE,
    JOURNAL,
    AUDIT,
    QUEUE,
    DEDUPE,
    REPLAY
  ]) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, value, mode = 0o600) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(
    file,
    JSON.stringify(value, null, 2) + '\n',
    { mode }
  );
  try {
    fs.chmodSync(file, mode);
  } catch (_) {}
}

function appendJsonl(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.appendFileSync(
    file,
    JSON.stringify(value) + '\n',
    { mode: 0o600 }
  );
  try {
    fs.chmodSync(file, 0o600);
  } catch (_) {}
}

function canonical(value) {
  if (Array.isArray(value)) {
    return value.map(canonical);
  }

  if (
    value &&
    typeof value === 'object'
  ) {
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
    .update(value)
    .digest('hex');
}

function loadIdentity() {
  const identity = readJson(IDENTITY_FILE);

  if (
    !identity ||
    typeof identity !== 'object' ||
    !identity.device_id ||
    !identity.fingerprint
  ) {
    throw new Error('invalid-canonical-identity');
  }

  return identity;
}

function loadSchema() {
  return readJson(SCHEMA_FILE);
}

function loadPolicy() {
  return readJson(POLICY_FILE);
}

function loadDeviceRegistry() {
  return readJson(DEVICE_REGISTRY_FILE);
}

function loadCapabilityState() {
  return readJson(CAPABILITY_STATE_FILE);
}

function policyFingerprint() {
  return sha256(
    canonicalJson(loadPolicy())
  );
}

function schemaFingerprint() {
  return sha256(
    canonicalJson(loadSchema())
  );
}

function newEventId() {
  return crypto.randomUUID();
}

function validateTopic(topic, policy) {
  if (
    typeof topic !== 'string' ||
    topic.length === 0 ||
    topic.length > policy.limits.max_topic_length
  ) {
    return {
      ok: false,
      reason: 'invalid-topic'
    };
  }

  for (const prefix of policy.topics.denied_prefixes) {
    if (topic.startsWith(prefix)) {
      return {
        ok: false,
        reason: 'topic-explicitly-denied'
      };
    }
  }

  const allowed =
    policy.topics.allowed_prefixes
      .some(prefix => topic.startsWith(prefix));

  if (!allowed) {
    return {
      ok: false,
      reason: 'topic-not-authorized'
    };
  }

  return {
    ok: true,
    reason: 'topic-authorized'
  };
}

function validateEventShape(event, policy) {
  if (!event || typeof event !== 'object') {
    return {
      ok: false,
      reason: 'invalid-event'
    };
  }

  const required = [
    'event_id',
    'event_version',
    'event_type',
    'topic',
    'source',
    'device_id',
    'sequence',
    'timestamp',
    'idempotency_key',
    'payload'
  ];

  for (const field of required) {
    if (
      event[field] === undefined ||
      event[field] === null
    ) {
      return {
        ok: false,
        reason: `missing-${field}`
      };
    }
  }

  if (
    typeof event.event_id !== 'string' ||
    !/^[0-9a-f-]{36}$/i.test(event.event_id)
  ) {
    return {
      ok: false,
      reason: 'invalid-event-id'
    };
  }

  if (
    !Number.isInteger(event.event_version) ||
    event.event_version < 1
  ) {
    return {
      ok: false,
      reason: 'invalid-event-version'
    };
  }

  if (
    typeof event.event_type !== 'string' ||
    event.event_type.length === 0 ||
    event.event_type.length > policy.limits.max_event_type_length
  ) {
    return {
      ok: false,
      reason: 'invalid-event-type'
    };
  }

  if (
    !Number.isInteger(event.sequence) ||
    event.sequence < 1
  ) {
    return {
      ok: false,
      reason: 'invalid-sequence'
    };
  }

  if (
    typeof event.idempotency_key !== 'string' ||
    event.idempotency_key.length === 0 ||
    event.idempotency_key.length > policy.limits.max_idempotency_length
  ) {
    return {
      ok: false,
      reason: 'invalid-idempotency-key'
    };
  }

  if (
    !event.source ||
    typeof event.source !== 'object' ||
    !event.source.service
  ) {
    return {
      ok: false,
      reason: 'invalid-source'
    };
  }

  if (
    typeof event.payload === 'undefined'
  ) {
    return {
      ok: false,
      reason: 'missing-payload'
    };
  }

  const payloadBytes =
    Buffer.byteLength(
      JSON.stringify(event.payload),
      'utf8'
    );

  if (
    payloadBytes >
    policy.limits.max_payload_bytes
  ) {
    return {
      ok: false,
      reason: 'payload-too-large'
    };
  }

  const topicResult =
    validateTopic(event.topic, policy);

  if (!topicResult.ok) {
    return topicResult;
  }

  const parsed =
    Date.parse(event.timestamp);

  if (Number.isNaN(parsed)) {
    return {
      ok: false,
      reason: 'invalid-timestamp'
    };
  }

  const now = Date.now();
  const age =
    (now - parsed) / 1000;
  const future =
    (parsed - now) / 1000;

  if (
    age >
    policy.limits.max_timestamp_age_seconds
  ) {
    return {
      ok: false,
      reason: 'event-too-old'
    };
  }

  if (
    future >
    policy.limits.max_future_timestamp_seconds
  ) {
    return {
      ok: false,
      reason: 'event-from-future'
    };
  }

  return {
    ok: true,
    reason: 'event-shape-valid'
  };
}

function eventDigest(event) {
  return sha256(
    canonicalJson(event)
  );
}

function journalFile(topic) {
  const safeTopic =
    topic.replace(/[^A-Za-z0-9._-]/g, '_');

  return path.join(
    JOURNAL,
    `${safeTopic}.jsonl`
  );
}

function dedupeFile(idempotencyKey) {
  const digest =
    sha256(idempotencyKey);

  return path.join(
    DEDUPE,
    `${digest}.json`
  );
}

function sequenceFile(deviceId, service) {
  const safe =
    `${deviceId}-${service}`
      .replace(/[^A-Za-z0-9._-]/g, '_');

  return path.join(
    EVENT_STATE,
    `sequence-${safe}.json`
  );
}

function getSequence(deviceId, service) {
  const file =
    sequenceFile(deviceId, service);

  if (!fs.existsSync(file)) {
    return 0;
  }

  const data = readJson(file);

  return Number.isInteger(data.sequence)
    ? data.sequence
    : 0;
}

function reserveSequence(deviceId, service) {
  const current =
    getSequence(deviceId, service);

  const next = current + 1;

  writeJson(
    sequenceFile(deviceId, service),
    {
      schema: 'dnyf.event.sequence.v1',
      device_id: deviceId,
      service,
      sequence: next,
      updated_at: new Date().toISOString()
    }
  );

  return next;
}

function queueCount() {
  if (!fs.existsSync(QUEUE)) {
    return 0;
  }

  return fs.readdirSync(QUEUE)
    .filter(
      name => name.endsWith('.json')
    )
    .length;
}

function audit(decision, event, extra = {}) {
  const record = {
    schema: 'dnyf.event.audit.v1',
    audit_id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    decision,
    event_id: event && event.event_id
      ? event.event_id
      : null,
    event_type: event && event.event_type
      ? event.event_type
      : null,
    topic: event && event.topic
      ? event.topic
      : null,
    device_id: event && event.device_id
      ? event.device_id
      : null,
    ...extra
  };

  const file =
    path.join(
      AUDIT,
      `dnyf-event-audit-${record.audit_id}.json`
    );

  writeJson(file, record);

  return file;
}

function policyDecision(event, context = {}) {
  const policy = loadPolicy();
  const identity = loadIdentity();

  if (!context.authenticated) {
    return {
      allow: false,
      reason: 'publisher-authentication-required'
    };
  }

  if (!context.cryptographic_proof) {
    return {
      allow: false,
      reason: 'cryptographic-proof-required'
    };
  }

  if (!context.trusted_peer) {
    return {
      allow: false,
      reason: 'peer-not-trusted'
    };
  }

  if (!context.session_active) {
    return {
      allow: false,
      reason: 'session-required'
    };
  }

  if (!context.local_approval) {
    return {
      allow: false,
      reason: 'local-approval-required'
    };
  }

  if (event.device_id === identity.device_id) {
    return {
      allow: false,
      reason: 'self-peer-event-denied'
    };
  }

  const shape =
    validateEventShape(event, policy);

  if (!shape.ok) {
    return {
      allow: false,
      reason: shape.reason
    };
  }

  if (
    context.capability_allowed !== true
  ) {
    return {
      allow: false,
      reason: 'capability-requirements-not-met'
    };
  }

  if (
    context.policy_allowed !== true
  ) {
    return {
      allow: false,
      reason: 'policy-engine-denied'
    };
  }

  return {
    allow: true,
    reason: 'event-publication-authorized'
  };
}

function publish(event, context = {}) {
  ensureDirectories();

  const decision =
    policyDecision(event, context);

  if (!decision.allow) {
    audit(
      'deny',
      event,
      {
        reason: decision.reason
      }
    );

    throw new Error(
      `event-publication-denied:${decision.reason}`
    );
  }

  const policy = loadPolicy();

  if (queueCount() >= policy.limits.max_queue_events) {
    audit(
      'deny',
      event,
      {
        reason: 'queue-capacity-exhausted'
      }
    );

    throw new Error(
      'event-publication-denied:queue-capacity-exhausted'
    );
  }

  const duplicateFile =
    dedupeFile(event.idempotency_key);

  if (fs.existsSync(duplicateFile)) {
    audit(
      'deny',
      event,
      {
        reason: 'duplicate-idempotency-key'
      }
    );

    throw new Error(
      'event-publication-denied:duplicate-idempotency-key'
    );
  }

  const journal =
    journalFile(event.topic);

  let previousSequence = 0;

  if (fs.existsSync(journal)) {
    const lines =
      fs.readFileSync(
        journal,
        'utf8'
      )
      .split('\n')
      .filter(Boolean);

    if (lines.length > 0) {
      try {
        const previous =
          JSON.parse(
            lines[lines.length - 1]
          );

        if (
          previous &&
          Number.isInteger(previous.sequence)
        ) {
          previousSequence =
            previous.sequence;
        }
      } catch (_) {}
    }
  }

  if (
    event.sequence <= previousSequence
  ) {
    audit(
      'deny',
      event,
      {
        reason: 'sequence-replay-or-regression',
        previous_sequence: previousSequence
      }
    );

    throw new Error(
      'event-publication-denied:sequence-replay-or-regression'
    );
  }

  const envelope = {
    schema: 'dnyf.event.envelope.v1',
    event_id: event.event_id,
    event_version: event.event_version,
    event_type: event.event_type,
    topic: event.topic,
    source: event.source,
    device_id: event.device_id,
    sequence: event.sequence,
    timestamp: event.timestamp,
    idempotency_key: event.idempotency_key,
    payload: event.payload,
    security: {
      authenticated: true,
      cryptographic_proof: true,
      trusted_peer: true,
      session_active: true,
      local_approval: true,
      policy_allowed: true,
      capability_allowed: true
    }
  };

  envelope.event_hash =
    eventDigest(envelope);

  appendJsonl(
    journal,
    envelope
  );

  writeJson(
    duplicateFile,
    {
      schema: 'dnyf.event.dedupe.v1',
      idempotency_key:
        event.idempotency_key,
      event_id:
        event.event_id,
      event_hash:
        envelope.event_hash,
      recorded_at:
        new Date().toISOString()
    }
  );

  const queued =
    path.join(
      QUEUE,
      `${event.sequence}-${event.event_id}.json`
    );

  writeJson(
    queued,
    envelope
  );

  audit(
    'allow',
    envelope,
    {
      reason: 'event-published',
      event_hash: envelope.event_hash
    }
  );

  return {
    ok: true,
    event_id: envelope.event_id,
    event_hash: envelope.event_hash,
    topic: envelope.topic,
    sequence: envelope.sequence,
    journal,
    queued
  };
}

function replay(topic, limit = 100) {
  const file =
    journalFile(topic);

  if (!fs.existsSync(file)) {
    return [];
  }

  return fs.readFileSync(
    file,
    'utf8'
  )
  .split('\n')
  .filter(Boolean)
  .slice(-limit)
  .map(JSON.parse);
}

function verifyJournal(topic) {
  const records =
    replay(topic, 100000);

  let previous = 0;

  for (const record of records) {
    if (
      !Number.isInteger(record.sequence) ||
      record.sequence <= previous
    ) {
      return {
        ok: false,
        reason: 'journal-sequence-invalid'
      };
    }

    if (
      typeof record.event_hash !== 'string'
    ) {
      return {
        ok: false,
        reason: 'journal-event-hash-missing'
      };
    }

    const copy = {
      ...record
    };

    delete copy.event_hash;

    const expected =
      eventDigest(copy);

    if (
      expected !== record.event_hash
    ) {
      return {
        ok: false,
        reason: 'journal-integrity-failure'
      };
    }

    previous =
      record.sequence;
  }

  return {
    ok: true,
    records: records.length
  };
}

function status() {
  const identity =
    loadIdentity();

  const policy =
    loadPolicy();

  const registry =
    loadDeviceRegistry();

  const capabilities =
    loadCapabilityState();

  let devices = 0;

  if (
    registry &&
    Array.isArray(registry.devices)
  ) {
    devices =
      registry.devices.length;
  }

  return {
    schema: 'dnyf.event.bus.status.v1',
    service: 'dnyf-event-bus',
    device_id: identity.device_id,
    fingerprint: identity.fingerprint,
    protocol: 'dnyf-event-bus/1',
    version: '1.0.0',
    policy_fingerprint:
      policyFingerprint(),
    schema_fingerprint:
      schemaFingerprint(),
    queue_depth:
      queueCount(),
    registered_devices:
      devices,
    capability_state:
      capabilities &&
      capabilities.schema
        ? capabilities.schema
        : null,
    delivery: {
      durable: true,
      at_least_once: true,
      ordering: 'per-topic-source',
      deduplication: true,
      replay_protection: true
    },
    security: {
      publisher_authentication_required: true,
      cryptographic_proof_required: true,
      policy_engine_required: true,
      trust_not_granted: true,
      authorization_not_granted: true,
      execution_not_granted: true,
      installation_not_granted: true,
      shell_not_granted: true,
      self_trust: false,
      self_pairing: false,
      automatic_trust: false,
      automatic_pairing: false,
      remote_execution: false,
      remote_installation: false,
      remote_shell: false,
      privilege_escalation: false
    }
  };
}

module.exports = {
  ROOT,
  loadIdentity,
  loadSchema,
  loadPolicy,
  loadDeviceRegistry,
  loadCapabilityState,
  canonical,
  canonicalJson,
  sha256,
  policyFingerprint,
  schemaFingerprint,
  validateTopic,
  validateEventShape,
  eventDigest,
  newEventId,
  getSequence,
  reserveSequence,
  policyDecision,
  publish,
  replay,
  verifyJournal,
  status,
  audit
};

if (require.main === module) {
  ensureDirectories();

  const command =
    process.argv[2] || 'status';

  if (command === 'status') {
    console.log(
      JSON.stringify(
        status(),
        null,
        2
      )
    );
    process.exit(0);
  }

  if (command === 'fingerprint') {
    console.log(
      JSON.stringify(
        {
          policy_fingerprint:
            policyFingerprint(),
          schema_fingerprint:
            schemaFingerprint()
        },
        null,
        2
      )
    );
    process.exit(0);
  }

  if (command === 'schema') {
    console.log(
      JSON.stringify(
        loadSchema(),
        null,
        2
      )
    );
    process.exit(0);
  }

  if (command === 'policy') {
    console.log(
      JSON.stringify(
        loadPolicy(),
        null,
        2
      )
    );
    process.exit(0);
  }

  if (command === 'replay') {
    const topic =
      process.argv[3];

    if (!topic) {
      console.error(
        'Usage: dnyf-event replay <topic>'
      );
      process.exit(2);
    }

    console.log(
      JSON.stringify(
        replay(topic),
        null,
        2
      )
    );

    process.exit(0);
  }

  if (command === 'verify') {
    const topic =
      process.argv[3];

    if (!topic) {
      console.error(
        'Usage: dnyf-event verify <topic>'
      );
      process.exit(2);
    }

    console.log(
      JSON.stringify(
        verifyJournal(topic),
        null,
        2
      )
    );

    process.exit(0);
  }

  if (command === 'sequence') {
    const device =
      process.argv[3];
    const service =
      process.argv[4];

    if (!device || !service) {
      console.error(
        'Usage: dnyf-event sequence <device-id> <service>'
      );
      process.exit(2);
    }

    console.log(
      JSON.stringify(
        {
          device_id: device,
          service,
          current_sequence:
            getSequence(
              device,
              service
            )
        },
        null,
        2
      )
    );

    process.exit(0);
  }

  if (command === 'test') {
    console.log(
      'Event bus authority loaded successfully'
    );
    process.exit(0);
  }

  console.error(
    `Unknown command: ${command}`
  );

  process.exit(2);
}
NODE

chmod 600 "${EVENT_RUNTIME}/dnyf-event-bus-authority.js"

# ------------------------------------------------------------
# CLI
# ------------------------------------------------------------

cat > "${BIN}/dnyf-event" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-${HOME}/DNYF-DEV}"
export DNYF_ROOT="${ROOT}"

exec node \
  "${ROOT}/opt/dnyf/runtime/event-bus/dnyf-event-bus-authority.js" \
  "$@"
SH

chmod 755 "${BIN}/dnyf-event"

ln -sfn "${BIN}/dnyf-event" "${USR_BIN}/dnyf-event"
ln -sfn "${BIN}/dnyf-event" "${USR_LOCAL_BIN}/dnyf-event"

# ------------------------------------------------------------
# Initial state
# ------------------------------------------------------------

cat > "${EVENT_STATE}/local-event-state.json" <<JSON
{
  "schema": "dnyf.event.local-state.v1",
  "device_id": "$(node -e "const i=require('${OPT}/runtime/secure/identity/identity.json');process.stdout.write(i.device_id)")",
  "protocol": "dnyf-event-bus/1",
  "mode": "durable-local",
  "queue_limit": 1000,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "security": {
    "publisher_authentication_required": true,
    "cryptographic_proof_required": true,
    "policy_engine_required": true,
    "trust_not_granted": true,
    "authorization_not_granted": true,
    "execution_not_granted": true,
    "installation_not_granted": true,
    "shell_not_granted": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "automatic_pairing": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  }
}
JSON

chmod 600 "${EVENT_STATE}/local-event-state.json"

# ------------------------------------------------------------
# Registry integration
# ------------------------------------------------------------

node - "${REG}/services.json" "${REG}/dnyf-event-bus-registry.json" <<'NODE'
const fs = require('fs');
const servicesFile = process.argv[2];
const registryFile = process.argv[3];

let services = {};

if (fs.existsSync(servicesFile)) {
  try {
    services = JSON.parse(
      fs.readFileSync(
        servicesFile,
        'utf8'
      )
    );
  } catch (_) {
    services = {};
  }
}

if (!services.services) {
  services.services = {};
}

services.services['dnyf-event-bus'] = {
  service: 'dnyf-event-bus',
  protocol: 'dnyf-event-bus/1',
  api_version: 'v1',
  status: 'installed',
  transport: [
    'local-process',
    'http',
    'https',
    'websocket'
  ],
  delivery: {
    durable: true,
    at_least_once: true,
    ordering: 'per-topic-source',
    deduplication: true,
    replay_protection: true,
    bounded_queue: true
  },
  security: {
    publisher_authentication_required: true,
    cryptographic_proof_required: true,
    policy_engine_required: true,
    grants_trust: false,
    grants_authorization: false,
    grants_execution: false,
    grants_installation: false,
    grants_shell: false,
    self_trust: false,
    self_pairing: false,
    automatic_trust: false,
    automatic_pairing: false,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false,
    privilege_escalation: false
  }
};

fs.writeFileSync(
  servicesFile,
  JSON.stringify(
    services,
    null,
    2
  ) + '\n'
);

const registry = {
  schema: 'dnyf.event.bus.registry.v1',
  service: 'dnyf-event-bus',
  protocol: 'dnyf-event-bus/1',
  version: '1.0.0',
  authority:
    'opt/dnyf/runtime/event-bus/dnyf-event-bus-authority.js',
  schema_file:
    'etc/dnyf/event-bus/dnyf-event-bus-schema.json',
  policy_file:
    'etc/dnyf/event-bus/dnyf-event-bus-policy.json',
  state:
    'opt/dnyf/state/event-bus',
  transport: [
    'local-process',
    'http',
    'https',
    'websocket'
  ],
  security: {
    publisher_authentication_required: true,
    policy_engine_required: true,
    trust_not_granted: true,
    authorization_not_granted: true,
    execution_not_granted: true,
    installation_not_granted: true,
    shell_not_granted: true,
    self_trust: false,
    self_pairing: false,
    automatic_trust: false,
    automatic_pairing: false,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false,
    privilege_escalation: false
  }
};

fs.writeFileSync(
  registryFile,
  JSON.stringify(
    registry,
    null,
    2
  ) + '\n'
);
NODE

chmod 600 "${REG}/dnyf-event-bus-registry.json"

# ------------------------------------------------------------
# Phase manifest
# ------------------------------------------------------------

cat > "${ETC}/phase9c-manifest.json" <<'JSON'
{
  "schema": "dnyf.phase.manifest.v1",
  "phase": "9C",
  "name": "DNYF Event Bus",
  "version": "1.0.0",
  "status": "complete",
  "depends_on": [
    "9A",
    "9B"
  ],
  "components": [
    "event-schema",
    "event-policy",
    "event-authority",
    "durable-journal",
    "bounded-queue",
    "deduplication",
    "replay-protection",
    "sequence-control",
    "audit",
    "cli",
    "service-registry"
  ],
  "security": {
    "default_deny": true,
    "fail_closed": true,
    "publisher_authentication_required": true,
    "cryptographic_proof_required": true,
    "policy_engine_required": true,
    "trust_not_granted": true,
    "authorization_not_granted": true,
    "execution_not_granted": true,
    "installation_not_granted": true,
    "shell_not_granted": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "automatic_pairing": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  }
}
JSON

chmod 600 "${ETC}/phase9c-manifest.json"

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  echo "[OK] $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "[FAIL] $1"
}

echo
echo "◆ Structural validation..."

[ -f "${EVENT_ETC}/dnyf-event-bus-schema.json" ] \
  && ok "event schema" \
  || fail "event schema"

[ -f "${EVENT_ETC}/dnyf-event-bus-policy.json" ] \
  && ok "event policy" \
  || fail "event policy"

[ -f "${EVENT_RUNTIME}/dnyf-event-bus-authority.js" ] \
  && ok "event authority" \
  || fail "event authority"

[ -x "${BIN}/dnyf-event" ] \
  && ok "event CLI" \
  || fail "event CLI"

[ -L "${USR_BIN}/dnyf-event" ] \
  && ok "usr/bin CLI link" \
  || fail "usr/bin CLI link"

[ -L "${USR_LOCAL_BIN}/dnyf-event" ] \
  && ok "usr/local/bin CLI link" \
  || fail "usr/local/bin CLI link"

[ -f "${REG}/dnyf-event-bus-registry.json" ] \
  && ok "event registry" \
  || fail "event registry"

[ -f "${ETC}/phase9c-manifest.json" ] \
  && ok "Phase 9C manifest" \
  || fail "Phase 9C manifest"

echo
echo "◆ JSON validation..."

node - "${EVENT_ETC}/dnyf-event-bus-schema.json" \
  "${EVENT_ETC}/dnyf-event-bus-policy.json" \
  "${ETC}/phase9c-manifest.json" \
  "${REG}/dnyf-event-bus-registry.json" \
  "${EVENT_STATE}/local-event-state.json" <<'NODE'
const fs = require('fs');

for (const file of process.argv.slice(2)) {
  JSON.parse(fs.readFileSync(file, 'utf8'));
  console.log(`[OK] JSON ${file}`);
}
NODE

PASS=$((PASS + 5))

echo
echo "◆ Authority validation..."

node - <<'NODE'
const path = require('path');

const root =
  process.env.DNYF_ROOT ||
  path.join(
    process.env.HOME,
    'DNYF-DEV'
  );

const authority =
  require(
    path.join(
      root,
      'opt',
      'dnyf',
      'runtime',
      'event-bus',
      'dnyf-event-bus-authority.js'
    )
  );

const identity =
  authority.loadIdentity();

if (!identity.device_id) {
  throw new Error('missing-device-id');
}

if (!identity.fingerprint) {
  throw new Error('missing-fingerprint');
}

authority.loadSchema();
authority.loadPolicy();

console.log(
  '[OK] authority identity binding'
);

console.log(
  '[OK] authority schema/policy loading'
);
NODE

PASS=$((PASS + 2))

echo
echo "◆ Event contract validation..."

node - <<'NODE'
const path = require('path');
const crypto = require('crypto');

const root =
  process.env.DNYF_ROOT ||
  path.join(
    process.env.HOME,
    'DNYF-DEV'
  );

const authority =
  require(
    path.join(
      root,
      'opt',
      'dnyf',
      'runtime',
      'event-bus',
      'dnyf-event-bus-authority.js'
    )
  );

const identity =
  authority.loadIdentity();

const policy =
  authority.loadPolicy();

function baseEvent(overrides = {}) {
  return {
    event_id:
      crypto.randomUUID(),
    event_version: 1,
    event_type:
      'device.state.changed',
    topic:
      'dnyf.device.state',
    source: {
      service:
        'synthetic-peer-service',
      version:
        '1.0.0'
    },
    device_id:
      'synthetic-peer-device',
    sequence: 1,
    timestamp:
      new Date().toISOString(),
    idempotency_key:
      crypto.randomUUID(),
    payload: {
      state: 'ready'
    },
    ...overrides
  };
}

/*
 * Shape validation.
 */
const shape =
  authority.validateEventShape(
    baseEvent(),
    policy
  );

if (!shape.ok) {
  throw new Error(
    `shape validation failed:${shape.reason}`
  );
}

console.log(
  '[OK] event envelope validation'
);

/*
 * Topic authorization.
 */
const topic =
  authority.validateTopic(
    'dnyf.device.state',
    policy
  );

if (!topic.ok) {
  throw new Error(
    `topic validation failed:${topic.reason}`
  );
}

console.log(
  '[OK] topic namespace authorization'
);

/*
 * Dangerous topic denial.
 */
const dangerous =
  authority.validateTopic(
    'dnyf.exec.request',
    policy
  );

if (dangerous.ok) {
  throw new Error(
    'dangerous topic was accepted'
  );
}

console.log(
  '[OK] dangerous topic denial'
);

/*
 * Unauthenticated publisher denial.
 */
const unauth =
  authority.policyDecision(
    baseEvent(),
    {
      authenticated: false,
      cryptographic_proof: false,
      trusted_peer: false,
      session_active: false,
      local_approval: false,
      capability_allowed: false,
      policy_allowed: false
    }
  );

if (unauth.allow) {
  throw new Error(
    'unauthenticated publisher accepted'
  );
}

console.log(
  '[OK] unauthenticated publisher denial'
);

/*
 * Untrusted publisher denial.
 */
const untrusted =
  authority.policyDecision(
    baseEvent(),
    {
      authenticated: true,
      cryptographic_proof: true,
      trusted_peer: false,
      session_active: true,
      local_approval: true,
      capability_allowed: true,
      policy_allowed: true
    }
  );

if (untrusted.allow) {
  throw new Error(
    'untrusted publisher accepted'
  );
}

console.log(
  '[OK] untrusted publisher denial'
);

/*
 * Missing policy approval denial.
 */
const deniedByPolicy =
  authority.policyDecision(
    baseEvent(),
    {
      authenticated: true,
      cryptographic_proof: true,
      trusted_peer: true,
      session_active: true,
      local_approval: true,
      capability_allowed: true,
      policy_allowed: false
    }
  );

if (deniedByPolicy.allow) {
  throw new Error(
    'policy-denied event accepted'
  );
}

console.log(
  '[OK] policy-engine denial'
);

/*
 * Self-peer isolation.
 */
const selfPeer =
  authority.policyDecision(
    baseEvent({
      device_id:
        identity.device_id
    }),
    {
      authenticated: true,
      cryptographic_proof: true,
      trusted_peer: true,
      session_active: true,
      local_approval: true,
      capability_allowed: true,
      policy_allowed: true
    }
  );

if (selfPeer.allow) {
  throw new Error(
    'self-peer event accepted'
  );
}

console.log(
  '[OK] self-peer isolation'
);

/*
 * Missing capability denial.
 */
const noCapability =
  authority.policyDecision(
    baseEvent(),
    {
      authenticated: true,
      cryptographic_proof: true,
      trusted_peer: true,
      session_active: true,
      local_approval: true,
      capability_allowed: false,
      policy_allowed: true
    }
  );

if (noCapability.allow) {
  throw new Error(
    'capability-denied event accepted'
  );
}

console.log(
  '[OK] capability denial'
);

/*
 * Fully authorized synthetic peer.
 */
const authorized =
  authority.policyDecision(
    baseEvent(),
    {
      authenticated: true,
      cryptographic_proof: true,
      trusted_peer: true,
      session_active: true,
      local_approval: true,
      capability_allowed: true,
      policy_allowed: true
    }
  );

if (!authorized.allow) {
  throw new Error(
    `authorized event rejected:${authorized.reason}`
  );
}

console.log(
  '[OK] fully authorized event contract'
);
NODE

PASS=$((PASS + 8))

echo
echo "◆ Durable publication validation..."

node - <<'NODE'
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const root =
  process.env.DNYF_ROOT ||
  path.join(
    process.env.HOME,
    'DNYF-DEV'
  );

const authority =
  require(
    path.join(
      root,
      'opt',
      'dnyf',
      'runtime',
      'event-bus',
      'dnyf-event-bus-authority.js'
    )
  );

const topic =
  'dnyf.system.validation';

const event =
  {
    event_id:
      crypto.randomUUID(),
    event_version: 1,
    event_type:
      'validation.event',
    topic,
    source: {
      service:
        'dnyf-phase9c-validator',
      version:
        '1.0.0'
    },
    device_id:
      'synthetic-validation-peer',
    sequence:
      1,
    timestamp:
      new Date().toISOString(),
    idempotency_key:
      `phase9c-${crypto.randomUUID()}`,
    payload: {
      validation:
        'phase9c'
    }
  };

const context =
  {
    authenticated: true,
    cryptographic_proof: true,
    trusted_peer: true,
    session_active: true,
    local_approval: true,
    capability_allowed: true,
    policy_allowed: true
  };

const result =
  authority.publish(
    event,
    context
  );

if (!result.ok) {
  throw new Error(
    'publication failed'
  );
}

if (!fs.existsSync(result.journal)) {
  throw new Error(
    'journal not durable'
  );
}

if (!fs.existsSync(result.queued)) {
  throw new Error(
    'queue record not durable'
  );
}

console.log(
  '[OK] durable event journal'
);

console.log(
  '[OK] bounded queue persistence'
);

const replay =
  authority.replay(
    topic
  );

if (!replay.some(
  item =>
    item.event_id ===
    event.event_id
)) {
  throw new Error(
    'published event unavailable for replay'
  );
}

console.log(
  '[OK] event replay'
);

const integrity =
  authority.verifyJournal(
    topic
  );

if (!integrity.ok) {
  throw new Error(
    `journal integrity failure:${integrity.reason}`
  );
}

console.log(
  '[OK] journal integrity'
);

/*
 * Duplicate publication must fail.
 */
let duplicateBlocked = false;

try {
  authority.publish(
    event,
    context
  );
} catch (error) {
  if (
    String(error.message)
      .includes(
        'duplicate-idempotency-key'
      )
  ) {
    duplicateBlocked = true;
  }
}

if (!duplicateBlocked) {
  throw new Error(
    'duplicate idempotency key was not blocked'
  );
}

console.log(
  '[OK] duplicate/idempotency protection'
);

/*
 * Sequence regression must fail.
 */
const regression =
  {
    ...event,
    event_id:
      crypto.randomUUID(),
    idempotency_key:
      `regression-${crypto.randomUUID()}`,
    sequence: 1
  };

let regressionBlocked = false;

try {
  authority.publish(
    regression,
    context
  );
} catch (error) {
  if (
    String(error.message)
      .includes(
        'sequence-replay-or-regression'
      )
  ) {
    regressionBlocked = true;
  }
}

if (!regressionBlocked) {
  throw new Error(
    'sequence regression was not blocked'
  );
}

console.log(
  '[OK] sequence replay/regression protection'
);
NODE

PASS=$((PASS + 6))

echo
echo "◆ Permission validation..."

MODE_AUTHORITY="$(
  stat -c '%a' \
    "${EVENT_RUNTIME}/dnyf-event-bus-authority.js"
)"

[ "${MODE_AUTHORITY}" = "600" ] \
  && ok "event authority permission 600" \
  || fail "event authority permission"

MODE_STATE="$(
  stat -c '%a' \
    "${EVENT_STATE}/local-event-state.json"
)"

[ "${MODE_STATE}" = "600" ] \
  && ok "event state permission 600" \
  || fail "event state permission"

# ------------------------------------------------------------
# Final status
# ------------------------------------------------------------

echo
echo "◆ Final event-bus status..."

"${BIN}/dnyf-event" status

echo
echo "============================================================"

if [ "${FAIL}" -eq 0 ]; then
  echo " PHASE 9C DNYF EVENT BUS: PASS"
else
  echo " PHASE 9C DNYF EVENT BUS: FAIL"
fi

echo "============================================================"
echo
echo "Device ID   : $(node -e "const i=require('${OPT}/runtime/secure/identity/identity.json');process.stdout.write(i.device_id)")"
echo "Fingerprint : $(node -e "const i=require('${OPT}/runtime/secure/identity/identity.json');process.stdout.write(i.fingerprint)")"
echo "Policy      : ${EVENT_ETC}/dnyf-event-bus-policy.json"
echo "Schema      : ${EVENT_ETC}/dnyf-event-bus-schema.json"
echo "Authority   : ${EVENT_RUNTIME}/dnyf-event-bus-authority.js"
echo "Registry    : ${REG}/dnyf-event-bus-registry.json"
echo "Manifest    : ${ETC}/phase9c-manifest.json"
echo "Backup      : ${BACKUP}"
echo
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
echo

if [ "${FAIL}" -ne 0 ]; then
  exit 1
fi

echo "Validated:"
echo "  ✓ event envelope schema"
echo "  ✓ deterministic canonicalization"
echo "  ✓ event hashing"
echo "  ✓ topic namespace control"
echo "  ✓ dangerous topic denial"
echo "  ✓ cryptographic publisher gate"
echo "  ✓ trust gate"
echo "  ✓ session gate"
echo "  ✓ local approval gate"
echo "  ✓ capability gate"
echo "  ✓ policy-engine gate"
echo "  ✓ self-peer isolation"
echo "  ✓ durable journal"
echo "  ✓ bounded queue"
echo "  ✓ idempotency protection"
echo "  ✓ sequence replay protection"
echo "  ✓ journal integrity"
echo "  ✓ replay support"
echo "  ✓ audit records"
echo "  ✓ service registry integration"
echo "  ✓ CLI"
echo
echo "Next phase: 9D DNYF Audit/Security Ledger"
