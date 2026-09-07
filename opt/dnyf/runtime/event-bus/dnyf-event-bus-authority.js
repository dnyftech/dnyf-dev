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
