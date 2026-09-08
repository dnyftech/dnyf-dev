#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

ETC="$ROOT/etc/dnyf/task-runtime"
RUNTIME="$ROOT/opt/dnyf/runtime/task-runtime"
STATE="$ROOT/opt/dnyf/state/task-runtime"
REGISTRY="$ROOT/registry/dnyf-distributed-task-runtime-registry.json"
BIN="$ROOT/bin/dnyf-task"
USR_BIN="$ROOT/usr/bin/dnyf-task"
USR_LOCAL_BIN="$ROOT/usr/local/bin/dnyf-task"
SERVICES="$ROOT/registry/services.json"
MANIFEST="$ETC/dnyf-distributed-task-runtime-manifest.json"
BACKUP="$ROOT/backups/phase10-distributed-task-runtime/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p \
  "$ETC" \
  "$RUNTIME" \
  "$STATE/journal" \
  "$STATE/queue" \
  "$STATE/dedupe" \
  "$STATE/replay" \
  "$STATE/dead-letter" \
  "$STATE/audit" \
  "$STATE/checkpoints" \
  "$STATE/results" \
  "$STATE/locks" \
  "$ROOT/backups/phase10-distributed-task-runtime"

mkdir -p "$BACKUP"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 10 DISTRIBUTED TASK RUNTIME"
echo "============================================================"
echo
echo "Root: $ROOT"
echo

###############################################################################
# 1. SCHEMA
###############################################################################

cat > "$ETC/dnyf-distributed-task-runtime-schema.json" <<'JSON'
{
  "schema": "dnyf.task.runtime.schema.v1",
  "protocol": "dnyf-task-runtime/1",
  "version": "1.0.0",
  "task": {
    "required": [
      "task_id",
      "created_at",
      "source_device_id",
      "operation",
      "priority",
      "state"
    ],
    "states": [
      "created",
      "queued",
      "scheduled",
      "authorized",
      "dispatched",
      "running",
      "completed",
      "failed",
      "retry_wait",
      "cancelled",
      "expired",
      "dead_letter"
    ]
  },
  "correlation": {
    "required": [
      "task_id"
    ],
    "optional": [
      "parent_task_id",
      "request_id",
      "event_id",
      "session_id",
      "policy_decision_id",
      "audit_record_id"
    ]
  },
  "routing": {
    "selection": [
      "device",
      "service",
      "capability",
      "resource"
    ],
    "ordering": [
      "explicit_device",
      "capability_match",
      "service_match",
      "resource_fit",
      "local_preference"
    ]
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
  }
}
JSON

###############################################################################
# 2. POLICY
###############################################################################

cat > "$ETC/dnyf-distributed-task-runtime-policy.json" <<'JSON'
{
  "schema": "dnyf.task.runtime.policy.v1",
  "protocol": "dnyf-task-runtime/1",
  "version": "1.0.0",
  "defaults": {
    "authorization": "deny",
    "execution": "disabled",
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  },
  "security": {
    "cryptographic_authentication_required": true,
    "authenticated_session_required": true,
    "policy_engine_required": true,
    "capability_validation_required": true,
    "device_registry_required": true,
    "service_discovery_required": true,
    "event_bus_required": true,
    "audit_ledger_required": true,
    "local_approval_required": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "automatic_pairing": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  },
  "dangerous_operations": [
    "execute",
    "shell",
    "install",
    "uninstall",
    "privilege",
    "sudo",
    "su",
    "kernel",
    "raw-device"
  ],
  "limits": {
    "max_retry_count": 5,
    "max_queue_depth": 1024,
    "max_task_age_seconds": 86400,
    "default_timeout_seconds": 300,
    "max_timeout_seconds": 3600,
    "max_payload_bytes": 1048576
  },
  "placement": {
    "prefer_local": true,
    "prefer_lan": true,
    "require_capability_match": true,
    "require_fresh_capability": true,
    "require_trusted_device": true,
    "require_authorized_session": true
  }
}
JSON

###############################################################################
# 3. MANIFEST
###############################################################################

cat > "$MANIFEST" <<'JSON'
{
  "schema": "dnyf.phase.manifest.v1",
  "phase": "10",
  "name": "DNYF Distributed Task Runtime",
  "protocol": "dnyf-task-runtime/1",
  "version": "1.0.0",
  "dependencies": [
    "phase-8h-device-registry",
    "phase-8i-capability-negotiation",
    "phase-8j-service-discovery",
    "phase-9a-api-gateway",
    "phase-9b-policy-engine",
    "phase-9c-event-bus",
    "phase-9d-audit-security-ledger"
  ],
  "execution": {
    "enabled": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  },
  "features": [
    "task-schema",
    "task-state-machine",
    "persistent-queue",
    "scheduler",
    "capability-aware-placement",
    "device-aware-placement",
    "service-aware-placement",
    "resource-aware-placement",
    "idempotency",
    "retry-backoff",
    "dead-letter",
    "cancellation",
    "timeout",
    "restart-recovery",
    "event-correlation",
    "audit-correlation"
  ]
}
JSON

###############################################################################
# 4. INITIAL STATE
###############################################################################

cat > "$STATE/local-task-runtime-state.json" <<'JSON'
{
  "schema": "dnyf.task.runtime.state.v1",
  "runtime_state": "ready",
  "next_sequence": 1,
  "queued": 0,
  "scheduled": 0,
  "running": 0,
  "completed": 0,
  "failed": 0,
  "retry_wait": 0,
  "cancelled": 0,
  "expired": 0,
  "dead_letter": 0,
  "execution_enabled": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "privilege_escalation": false
}
JSON

chmod 600 "$STATE/local-task-runtime-state.json"

###############################################################################
# 5. AUTHORITY LIBRARY
###############################################################################

cat > "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<'JS'
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

const ETC = path.join(
  ROOT,
  'etc/dnyf/task-runtime'
);

/*
 * Production state remains canonical by default.
 *
 * Contract validation may explicitly provide an isolated state directory
 * through DNYF_TASK_CONTRACT_STATE. The override is accepted only when
 * it is an absolute path located beneath the canonical task-runtime
 * state directory, preventing arbitrary state redirection.
 */
const CANONICAL_STATE = path.join(
  ROOT,
  'opt/dnyf/state/task-runtime'
);

const CONTRACT_STATE = process.env.DNYF_TASK_CONTRACT_STATE;

const STATE =
  CONTRACT_STATE &&
  path.isAbsolute(CONTRACT_STATE) &&
  (
    CONTRACT_STATE === CANONICAL_STATE ||
    CONTRACT_STATE.startsWith(CANONICAL_STATE + path.sep)
  )
    ? CONTRACT_STATE
    : CANONICAL_STATE;

const SCHEMA_FILE = path.join(
  ETC,
  'dnyf-distributed-task-runtime-schema.json'
);

const POLICY_FILE = path.join(
  ETC,
  'dnyf-distributed-task-runtime-policy.json'
);

const STATE_FILE = path.join(
  STATE,
  'local-task-runtime-state.json'
);

const JOURNAL_DIR = path.join(
  STATE,
  'journal'
);

const QUEUE_DIR = path.join(
  STATE,
  'queue'
);

const DEDUPE_DIR = path.join(
  STATE,
  'dedupe'
);

const DEAD_DIR = path.join(
  STATE,
  'dead-letter'
);

const RESULTS_DIR = path.join(
  STATE,
  'results'
);

const CHECKPOINT_DIR = path.join(
  STATE,
  'checkpoints'
);

const LOCK_DIR = path.join(
  STATE,
  'locks'
);

const AUDIT_DIR = path.join(
  STATE,
  'audit'
);

for (const directory of [
  STATE,
  JOURNAL_DIR,
  QUEUE_DIR,
  DEDUPE_DIR,
  DEAD_DIR,
  RESULTS_DIR,
  CHECKPOINT_DIR,
  LOCK_DIR,
  AUDIT_DIR
]) {
  fs.mkdirSync(directory, { recursive: true });
}

function loadJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function saveJson(file, value, mode = 0o600) {
  const tmp =
    `${file}.tmp-${process.pid}-${Date.now()}`;

  fs.writeFileSync(
    tmp,
    JSON.stringify(value, null, 2) + '\n',
    { mode }
  );

  fs.chmodSync(tmp, mode);
  fs.renameSync(tmp, file);
}

function loadSchema() {
  return loadJson(SCHEMA_FILE);
}

function loadPolicy() {
  return loadJson(POLICY_FILE);
}

function loadState() {
  if (!fs.existsSync(STATE_FILE)) {
    const state = defaultState();
    saveState(state);
    return state;
  }

  return loadJson(STATE_FILE);
}

function saveState(state) {
  saveJson(STATE_FILE, state, 0o600);
}

function defaultState() {
  return {
    schema: 'dnyf.task.runtime.state.v1',
    version: '1.0.0',
    queue_depth: 0,
    created_tasks: 0,
    queued_tasks: 0,
    scheduled_tasks: 0,
    authorized_tasks: 0,
    dispatched_tasks: 0,
    running_tasks: 0,
    completed_tasks: 0,
    failed_tasks: 0,
    retry_wait_tasks: 0,
    cancelled_tasks: 0,
    expired_tasks: 0,
    dead_letter_tasks: 0,
    last_sequence: 0,
    last_journal_hash: null,
    updated_at: new Date().toISOString()
  };
}

function canonical(value) {
  if (value === null || typeof value !== 'object') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(canonical);
  }

  const result = {};

  for (const key of Object.keys(value).sort()) {
    result[key] = canonical(value[key]);
  }

  return result;
}

function canonicalJson(value) {
  return JSON.stringify(canonical(value));
}

function sha256(value) {
  return crypto
    .createHash('sha256')
    .update(
      typeof value === 'string'
        ? value
        : canonicalJson(value)
    )
    .digest('hex');
}

function taskHash(task) {
  return sha256({
    task_id: task.task_id,
    created_at: task.created_at,
    source_device_id: task.source_device_id,
    operation: task.operation,
    priority: task.priority,
    target: task.target || null,
    routing: task.routing || null,
    resource: task.resource || null,
    capability: task.capability || null,
    payload: task.payload || null
  });
}

function taskKey(task) {
  return sha256({
    source_device_id: task.source_device_id,
    operation: task.operation,
    target: task.target || null,
    routing: task.routing || null,
    resource: task.resource || null,
    capability: task.capability || null,
    payload: task.payload || null
  });
}

function isDangerousOperation(operation) {
  const value = String(operation || '').toLowerCase();

  return [
    'execute',
    'shell',
    'install',
    'uninstall',
    'privilege',
    'sudo',
    'su',
    'kernel',
    'raw-device'
  ].includes(value);
}

function validateTask(task) {
  const policy = loadPolicy();

  if (!task || typeof task !== 'object') {
    return {
      ok: false,
      reason: 'task_not_object'
    };
  }

  const required = [
    'task_id',
    'created_at',
    'source_device_id',
    'operation',
    'priority',
    'state'
  ];

  for (const field of required) {
    if (
      task[field] === undefined ||
      task[field] === null ||
      task[field] === ''
    ) {
      return {
        ok: false,
        reason: `missing_${field}`
      };
    }
  }

  if (isDangerousOperation(task.operation)) {
    return {
      ok: false,
      reason: 'dangerous_operation_disabled'
    };
  }

  if (
    policy.execution &&
    policy.execution.remote_execution === true
  ) {
    return {
      ok: false,
      reason: 'execution_policy_invalid'
    };
  }

  const payloadBytes =
    Buffer.byteLength(
      JSON.stringify(task.payload || null),
      'utf8'
    );

  const maxPayload =
    Number(policy.limits?.max_payload_bytes || 1048576);

  if (payloadBytes > maxPayload) {
    return {
      ok: false,
      reason: 'payload_too_large'
    };
  }

  const timeout =
    Number(task.timeout_seconds || 300);

  const maxTimeout =
    Number(policy.limits?.max_timeout_seconds || 3600);

  if (timeout < 1 || timeout > maxTimeout) {
    return {
      ok: false,
      reason: 'timeout_out_of_range'
    };
  }

  const retryCount =
    Number(task.retry_count || 0);

  const maxRetry =
    Number(policy.limits?.max_retry || 5);

  if (retryCount < 0 || retryCount > maxRetry) {
    return {
      ok: false,
      reason: 'retry_limit_exceeded'
    };
  }

  return {
    ok: true,
    payload_bytes: payloadBytes
  };
}

function buildTask(input) {
  const now = new Date().toISOString();

  const task = {
    task_id:
      input.task_id ||
      `task-${crypto.randomUUID()}`,

    created_at:
      input.created_at || now,

    source_device_id:
      input.source_device_id ||
      'unknown',

    operation:
      input.operation,

    priority:
      input.priority ?? 'normal',

    state:
      'created',

    target:
      input.target || null,

    routing:
      input.routing || null,

    resource:
      input.resource || null,

    capability:
      input.capability || null,

    payload:
      input.payload || null,

    timeout_seconds:
      Number(input.timeout_seconds || 300),

    retry_count:
      Number(input.retry_count || 0),

    parent_task_id:
      input.parent_task_id || null,

    request_id:
      input.request_id || null,

    event_id:
      input.event_id || null,

    session_id:
      input.session_id || null,

    policy_decision_id:
      input.policy_decision_id || null,

    audit_record_id:
      input.audit_record_id || null
  };

  task.task_hash = taskHash(task);
  task.idempotency_key = taskKey(task);

  return task;
}

function journalFile() {
  return path.join(
    JOURNAL_DIR,
    'dnyf-task-runtime-journal.jsonl'
  );
}

function readJournal() {
  const file = journalFile();

  if (!fs.existsSync(file)) {
    return [];
  }

  const lines =
    fs.readFileSync(file, 'utf8')
      .split('\n')
      .filter(Boolean);

  return lines.map(line => JSON.parse(line));
}

function appendJournal(type, task, extra = {}) {
  const records = readJournal();

  const sequence =
    records.length
      ? Number(records[records.length - 1].sequence) + 1
      : 1;

  const previousHash =
    records.length
      ? records[records.length - 1].record_hash
      : null;

  const record = {
    schema: 'dnyf.task.runtime.journal.v1',
    sequence,
    recorded_at: new Date().toISOString(),
    type,
    task_id: task.task_id,
    task_hash: task.task_hash,
    previous_hash: previousHash,
    state: task.state,
    task,
    ...extra
  };

  record.record_hash = sha256(record);

  fs.appendFileSync(
    journalFile(),
    JSON.stringify(record) + '\n',
    { mode: 0o600 }
  );

  fs.chmodSync(journalFile(), 0o600);

  const state = loadState();

  state.last_sequence = sequence;
  state.last_journal_hash = record.record_hash;
  state.updated_at = new Date().toISOString();

  saveState(state);

  return record;
}

function verifyJournal() {
  const records = readJournal();

  let previousHash = null;

  for (let index = 0; index < records.length; index++) {
    const record = records[index];

    if (Number(record.sequence) !== index + 1) {
      return {
        ok: false,
        reason: 'sequence_gap',
        sequence: record.sequence
      };
    }

    if ((record.previous_hash || null) !== previousHash) {
      return {
        ok: false,
        reason: 'previous_hash_mismatch',
        sequence: record.sequence
      };
    }

    const expected = record.record_hash;

    const copy = { ...record };
    delete copy.record_hash;

    const actual = sha256(copy);

    if (actual !== expected) {
      return {
        ok: false,
        reason: 'record_hash_mismatch',
        sequence: record.sequence
      };
    }

    previousHash = expected;
  }

  const state = loadState();

  if (
    Number(state.last_sequence || 0) !== records.length
  ) {
    return {
      ok: false,
      reason: 'state_sequence_mismatch'
    };
  }

  if (
    (state.last_journal_hash || null) !== previousHash
  ) {
    return {
      ok: false,
      reason: 'state_hash_mismatch'
    };
  }

  return {
    ok: true,
    records: records.length,
    last_sequence:
      records.length
        ? records[records.length - 1].sequence
        : 0,
    last_hash: previousHash
  };
}

function queueFile(task) {
  return path.join(
    QUEUE_DIR,
    `${task.task_id}.json`
  );
}

function dedupeFile(task) {
  return path.join(
    DEDUPE_DIR,
    `${task.idempotency_key}.json`
  );
}

function refreshQueueDepth() {
  const files =
    fs.readdirSync(QUEUE_DIR)
      .filter(name => name.endsWith('.json'));

  const state = loadState();

  state.queue_depth = files.length;
  state.updated_at = new Date().toISOString();

  saveState(state);

  return files.length;
}

function enqueue(task) {
  const validation = validateTask(task);

  if (!validation.ok) {
    throw new Error(validation.reason);
  }

  const existing =
    dedupeFile(task);

  if (fs.existsSync(existing)) {
    return {
      ok: true,
      duplicate: true,
      task: JSON.parse(
        fs.readFileSync(existing, 'utf8')
      )
    };
  }

  const queued = {
    ...task,
    state: 'queued',
    queued_at: new Date().toISOString()
  };

  fs.writeFileSync(
    queueFile(queued),
    JSON.stringify(queued, null, 2) + '\n',
    { mode: 0o600 }
  );

  fs.writeFileSync(
    existing,
    JSON.stringify({
      idempotency_key: queued.idempotency_key,
      task_id: queued.task_id,
      task_hash: queued.task_hash,
      created_at: queued.created_at
    }, null, 2) + '\n',
    { mode: 0o600 }
  );

  const state = loadState();

  state.created_tasks += 1;
  state.queued_tasks += 1;
  state.queue_depth += 1;
  state.updated_at = new Date().toISOString();

  saveState(state);

  appendJournal('enqueue', queued);

  return {
    ok: true,
    duplicate: false,
    task: queued
  };
}

function transition(task, nextState, type, extra = {}) {
  const updated = {
    ...task,
    state: nextState,
    updated_at: new Date().toISOString()
  };

  appendJournal(type, updated, extra);

  const state = loadState();

  const map = {
    scheduled: 'scheduled_tasks',
    authorized: 'authorized_tasks',
    dispatched: 'dispatched_tasks',
    running: 'running_tasks',
    completed: 'completed_tasks',
    failed: 'failed_tasks',
    retry_wait: 'retry_wait_tasks',
    cancelled: 'cancelled_tasks',
    expired: 'expired_tasks',
    dead_letter: 'dead_letter_tasks'
  };

  if (map[nextState]) {
    state[map[nextState]] += 1;
  }

  saveState(state);

  return updated;
}

function schedule(task) {
  return transition(
    task,
    'scheduled',
    'schedule'
  );
}

function authorize(task, decision = {}) {
  const allowed =
    decision.allowed === true;

  if (!allowed) {
    return transition(
      task,
      'failed',
      'authorization_denied',
      {
        authorization: 'denied',
        reason:
          decision.reason ||
          'default_deny'
      }
    );
  }

  return transition(
    task,
    'authorized',
    'authorize',
    {
      authorization: 'approved'
    }
  );
}

function dispatch(task) {
  if (task.state !== 'authorized') {
    throw new Error(
      'dispatch_requires_authorized_task'
    );
  }

  if (isDangerousOperation(task.operation)) {
    throw new Error(
      'dangerous_operation_disabled'
    );
  }

  return transition(
    task,
    'dispatched',
    'dispatch',
    {
      execution_enabled: false
    }
  );
}

function retry(task, reason = 'retry_requested') {
  const policy = loadPolicy();

  const nextRetry =
    Number(task.retry_count || 0) + 1;

  const maxRetry =
    Number(policy.limits?.max_retry || 5);

  if (nextRetry > maxRetry) {
    return transition(
      {
        ...task,
        retry_count: nextRetry
      },
      'dead_letter',
      'dead_letter',
      { reason: 'retry_limit_exceeded' }
    );
  }

  return transition(
    {
      ...task,
      retry_count: nextRetry
    },
    'retry_wait',
    'retry',
    {
      reason,
      backoff_seconds:
        calculateBackoff(nextRetry)
    }
  );
}

function cancel(task, reason = 'cancelled') {
  return transition(
    task,
    'cancelled',
    'cancel',
    { reason }
  );
}

function expire(task, reason = 'task_expired') {
  return transition(
    task,
    'expired',
    'expire',
    { reason }
  );
}

function complete(task, result = null) {
  const completed =
    transition(
      task,
      'completed',
      'complete'
    );

  writeResult(
    completed,
    result
  );

  return completed;
}

function writeResult(task, result) {
  const file =
    path.join(
      RESULTS_DIR,
      `${task.task_id}.json`
    );

  saveJson(
    file,
    {
      schema: 'dnyf.task.runtime.result.v1',
      task_id: task.task_id,
      task_hash: task.task_hash,
      completed_at: new Date().toISOString(),
      execution_enabled: false,
      result
    },
    0o600
  );

  return file;
}

function calculateBackoff(retryCount) {
  const count =
    Math.max(0, Number(retryCount || 0));

  return Math.min(
    3600,
    Math.pow(2, count) * 5
  );
}

function status() {
  const state = loadState();
  const journal = verifyJournal();

  return {
    schema:
      'dnyf.task.runtime.status.v1',
    root: ROOT,
    state,
    journal,
    security: {
      execution_enabled: false,
      remote_execution: false,
      remote_installation: false,
      remote_shell: false,
      privilege_escalation: false,
      self_trust: false,
      self_pairing: false,
      automatic_trust: false
    }
  };
}

function test() {
  const originalState = loadState();

  const testTask =
    buildTask({
      task_id:
        `phase10-test-${process.pid}-${Date.now()}`,
      source_device_id:
        'phase10-contract-test',
      operation:
        'capability-check',
      priority:
        'normal',
      target:
        {
          device_id:
            'phase10-synthetic-peer'
        },
      routing:
        {
          mode:
            'capability'
        },
      resource:
        'cpu',
      capability:
        'task.runtime',
      payload:
        {
          test:
            true
        }
    });

  const validation =
    validateTask(testTask);

  if (!validation.ok) {
    throw new Error(
      `validation_failed:${validation.reason}`
    );
  }

  const dangerous =
    buildTask({
      task_id:
        `phase10-danger-${process.pid}-${Date.now()}`,
      source_device_id:
        'phase10-contract-test',
      operation:
        'shell',
      payload:
        {
          test:
            true
        }
    });

  const dangerousResult =
    validateTask(dangerous);

  if (
    dangerousResult.ok ||
    dangerousResult.reason !==
      'dangerous_operation_disabled'
  ) {
    throw new Error(
      'dangerous_operation_not_blocked'
    );
  }

  const before =
    verifyJournal();

  if (!before.ok) {
    throw new Error(
      `journal_before_invalid:${before.reason}`
    );
  }

  const queued =
    enqueue(testTask);

  const duplicate =
    enqueue(testTask);

  if (!duplicate.duplicate) {
    throw new Error(
      'idempotency_deduplication_failed'
    );
  }

  const scheduled =
    schedule(queued.task);

  const denied =
    authorize(
      scheduled,
      {
        allowed:
          false,
        reason:
          'phase10_default_deny_test'
      }
    );

  if (denied.state !== 'failed') {
    throw new Error(
      'default_deny_failed'
    );
  }

  const after =
    verifyJournal();

  if (!after.ok) {
    throw new Error(
      `journal_after_invalid:${after.reason}`
    );
  }

  const finalStatus =
    status();

  return {
    ok: true,
    validation: true,
    dangerous_operation_blocked: true,
    idempotency_deduplication: true,
    default_deny: true,
    journal_hash_chain: true,
    queue_depth:
      finalStatus.state.queue_depth,
    journal_records:
      finalStatus.journal.records,
    last_sequence:
      finalStatus.journal.last_sequence,
    execution_enabled: false,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false,
    privilege_escalation: false
  };
}

module.exports = {
  ROOT,
  loadSchema,
  loadPolicy,
  loadState,
  saveState,
  canonical,
  canonicalJson,
  sha256,
  taskHash,
  taskKey,
  isDangerousOperation,
  validateTask,
  buildTask,
  enqueue,
  schedule,
  authorize,
  dispatch,
  retry,
  cancel,
  expire,
  complete,
  writeResult,
  verifyJournal,
  calculateBackoff,
  status,
  test
};
JS
chmod 600 "$RUNTIME/dnyf-distributed-task-runtime-authority.js"

###############################################################################
# 6. CLI
###############################################################################

cat > "$BIN" <<'JS'
#!/data/data/com.termux/files/usr/bin/node

'use strict';

const fs = require('fs');
const path = require('path');

const ROOT =
  process.env.DNYF_ROOT &&
  process.env.DNYF_ROOT.endsWith('/DNYF-DEV')
    ? process.env.DNYF_ROOT
    : path.resolve(
        __dirname,
        '..'
      );

const AUTHORITY =
  path.join(
    ROOT,
    'opt/dnyf/runtime/task-runtime',
    'dnyf-distributed-task-runtime-authority.js'
  );

if (!fs.existsSync(AUTHORITY)) {
  console.error(
    `[DNYF] Task runtime authority not found: ${AUTHORITY}`
  );
  process.exit(1);
}

const runtime =
  require(AUTHORITY);

const command =
  process.argv[2] || 'status';

function inputJson(argument) {
  if (!argument) {
    throw new Error(
      'JSON argument required'
    );
  }

  return JSON.parse(argument);
}

function print(value) {
  if (
    typeof value === 'string'
  ) {
    console.log(value);
    return;
  }

  console.log(
    JSON.stringify(
      value,
      null,
      2
    )
  );
}

try {
  switch (command) {
    case 'status':
      print(runtime.status());
      break;

    case 'schema':
      print(runtime.loadSchema());
      break;

    case 'policy':
      print(runtime.loadPolicy());
      break;

    case 'fingerprint': {
      const schema =
        runtime.loadSchema();

      const policy =
        runtime.loadPolicy();

      print({
        schema:
          'dnyf.task.runtime.fingerprint.v1',
        schema_sha256:
          runtime.sha256(schema),
        policy_sha256:
          runtime.sha256(policy),
        authority:
          'dnyf-distributed-task-runtime/1'
      });
      break;
    }

    case 'test':
      print(runtime.test());
      break;

    case 'verify':
      print(runtime.verifyJournal());
      break;

    case 'create':
      print(
        runtime.buildTask(
          inputJson(
            process.argv[3]
          )
        )
      );
      break;

    case 'enqueue':
      print(
        runtime.enqueue(
          runtime.buildTask(
            inputJson(
              process.argv[3]
            )
          )
        )
      );
      break;

    default:
      console.error(
        [
          'DNYF Distributed Task Runtime',
          '',
          'Usage:',
          '  dnyf-task status',
          '  dnyf-task schema',
          '  dnyf-task policy',
          '  dnyf-task fingerprint',
          '  dnyf-task test',
          '  dnyf-task verify',
          '  dnyf-task create <json>',
          '  dnyf-task enqueue <json>'
        ].join('\n')
      );

      process.exit(2);
  }
} catch (error) {
  console.error(
    `[DNYF] ${error.message}`
  );

  process.exit(1);
}
JS

chmod 700 "$BIN"

ln -sfn "$BIN" "$USR_BIN"
ln -sfn "$BIN" "$USR_LOCAL_BIN"

###############################################################################
# 7. REGISTRY
###############################################################################

cat > "$REGISTRY" <<'JSON'
{
  "schema": "dnyf.distributed.task.runtime.registry.v1",
  "service": "dnyf-distributed-task-runtime",
  "protocol": "dnyf-task-runtime/1",
  "version": "1.0.0",
  "cli": "dnyf-task",
  "runtime": "opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js",
  "schema_file": "etc/dnyf/task-runtime/dnyf-distributed-task-runtime-schema.json",
  "policy_file": "etc/dnyf/task-runtime/dnyf-distributed-task-runtime-policy.json",
  "state_directory": "opt/dnyf/state/task-runtime",
  "capabilities": [
    "task-creation",
    "task-validation",
    "task-queueing",
    "task-scheduling",
    "capability-aware-placement",
    "device-aware-placement",
    "service-aware-placement",
    "retry",
    "dead-letter",
    "cancellation",
    "timeout",
    "restart-recovery",
    "idempotency",
    "event-correlation",
    "audit-correlation"
  ],
  "security": {
    "execution_enabled": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "automatic_pairing": false,
    "trust_grant": false,
    "authorization_grant": false,
    "policy_bypass": false
  },
  "dependencies": {
    "device_registry": "phase-8h",
    "capability_negotiation": "phase-8i",
    "service_discovery": "phase-8j",
    "api_gateway": "phase-9a",
    "policy_engine": "phase-9b",
    "event_bus": "phase-9c",
    "audit_security_ledger": "phase-9d"
  }
}
JSON

###############################################################################
# 8. SERVICES REGISTRY
###############################################################################

cp -a "$SERVICES" "$BACKUP/services.json" 2>/dev/null || true

node - "$SERVICES" <<'NODE'
const fs = require('fs');
const file = process.argv[2];

let data = {};
if (fs.existsSync(file)) {
  data = JSON.parse(fs.readFileSync(file, 'utf8'));
}

if (!Array.isArray(data.services)) {
  data.services = [];
}

const service = {
  name: 'dnyf-distributed-task-runtime',
  protocol: 'dnyf-task-runtime/1',
  version: '1.0.0',
  status: 'registered',
  transport: ['local-process', 'http', 'https', 'websocket'],
  execution_enabled: false,
  remote_execution: false,
  remote_installation: false,
  remote_shell: false,
  privilege_escalation: false
};

const index =
  data.services.findIndex(
    item =>
      item &&
      item.name === service.name
  );

if (index >= 0) {
  data.services[index] = {
    ...data.services[index],
    ...service
  };
} else {
  data.services.push(service);
}

fs.writeFileSync(
  file,
  JSON.stringify(data, null, 2) + '\n'
);
NODE

###############################################################################
# 9. PERMISSIONS
###############################################################################

chmod 600 \
  "$ETC/dnyf-distributed-task-runtime-schema.json" \
  "$ETC/dnyf-distributed-task-runtime-policy.json" \
  "$MANIFEST" \
  "$REGISTRY"

chmod 600 "$RUNTIME/dnyf-distributed-task-runtime-authority.js"

###############################################################################
# 10. VALIDATION
###############################################################################

echo "◆ Structural validation..."

for file in \
  "$ETC/dnyf-distributed-task-runtime-schema.json" \
  "$ETC/dnyf-distributed-task-runtime-policy.json" \
  "$MANIFEST" \
  "$RUNTIME/dnyf-distributed-task-runtime-authority.js" \
  "$STATE/local-task-runtime-state.json" \
  "$BIN" \
  "$REGISTRY"
do
  test -f "$file"
  echo "[OK] exists: ${file#$ROOT/}"
done

test -L "$USR_BIN"
test -L "$USR_LOCAL_BIN"

echo "[OK] usr/bin task CLI link"
echo "[OK] usr/local/bin task CLI link"

echo
echo "◆ JSON validation..."

for file in \
  "$ETC/dnyf-distributed-task-runtime-schema.json" \
  "$ETC/dnyf-distributed-task-runtime-policy.json" \
  "$MANIFEST" \
  "$STATE/local-task-runtime-state.json" \
  "$REGISTRY"
do
  node -e \
    "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" \
    "$file"

  echo "[OK] JSON ${file#$ROOT/}"
done

echo
echo "◆ Syntax validation..."

node --check \
  "$RUNTIME/dnyf-distributed-task-runtime-authority.js"

node --check "$BIN"

echo "[OK] task authority syntax"
echo "[OK] task CLI syntax"

echo
echo "◆ Permission validation..."

test "$(stat -c '%a' "$RUNTIME/dnyf-distributed-task-runtime-authority.js")" = "600"
echo "[OK] task authority permission 600"

test "$(stat -c '%a' "$STATE/local-task-runtime-state.json")" = "600"
echo "[OK] task state permission 600"

echo
echo "◆ Security contract validation..."

node - "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<'NODE'
const authority = require(process.argv[2]);
const policy = authority.loadPolicy();
const schema = authority.loadSchema();

if (policy.defaults.authorization !== 'deny')
  throw new Error('default-deny-missing');

if (policy.defaults.execution !== 'disabled')
  throw new Error('execution-not-disabled');

if (policy.security.remote_execution !== false)
  throw new Error('remote-execution-enabled');

if (policy.security.remote_installation !== false)
  throw new Error('remote-installation-enabled');

if (policy.security.remote_shell !== false)
  throw new Error('remote-shell-enabled');

if (policy.security.privilege_escalation !== false)
  throw new Error('privilege-escalation-enabled');

if (policy.security.self_trust !== false)
  throw new Error('self-trust-enabled');

if (policy.security.self_pairing !== false)
  throw new Error('self-pairing-enabled');

if (policy.security.automatic_trust !== false)
  throw new Error('automatic-trust-enabled');

if (!schema.task.states.includes('created'))
  throw new Error('task-state-machine-missing');

if (!schema.task.states.includes('dead_letter'))
  throw new Error('dead-letter-state-missing');

console.log('[OK] default deny');
console.log('[OK] execution disabled');
console.log('[OK] remote execution disabled');
console.log('[OK] remote installation disabled');
console.log('[OK] remote shell disabled');
console.log('[OK] privilege escalation disabled');
console.log('[OK] self-trust disabled');
console.log('[OK] self-pairing disabled');
console.log('[OK] automatic trust disabled');
console.log('[OK] task lifecycle schema');
console.log('[OK] dead-letter lifecycle');
NODE

echo
echo "◆ Task runtime contract validation..."

# Contract tests must always begin from a clean runtime journal/state.
# The runtime itself enforces sequence continuity, so stale validation
# records must never be mixed with a freshly initialized state file.

CONTRACT_STATE_DIR="$STATE/contract-validation"
CONTRACT_JOURNAL_DIR="$CONTRACT_STATE_DIR/journal"
CONTRACT_QUEUE_DIR="$CONTRACT_STATE_DIR/queue"
CONTRACT_DEDUPE_DIR="$CONTRACT_STATE_DIR/dedupe"
CONTRACT_REPLAY_DIR="$CONTRACT_STATE_DIR/replay"
CONTRACT_DEADLETTER_DIR="$CONTRACT_STATE_DIR/dead-letter"
CONTRACT_AUDIT_DIR="$CONTRACT_STATE_DIR/audit"
CONTRACT_CHECKPOINT_DIR="$CONTRACT_STATE_DIR/checkpoints"
CONTRACT_RESULTS_DIR="$CONTRACT_STATE_DIR/results"
CONTRACT_LOCK_DIR="$CONTRACT_STATE_DIR/locks"

rm -rf "$CONTRACT_STATE_DIR"

mkdir -p   "$CONTRACT_JOURNAL_DIR"   "$CONTRACT_QUEUE_DIR"   "$CONTRACT_DEDUPE_DIR"   "$CONTRACT_REPLAY_DIR"   "$CONTRACT_DEADLETTER_DIR"   "$CONTRACT_AUDIT_DIR"   "$CONTRACT_CHECKPOINT_DIR"   "$CONTRACT_RESULTS_DIR"   "$CONTRACT_LOCK_DIR"

# Preserve production state while directing contract validation to
# an isolated clean state tree.
CONTRACT_STATE_FILE="$CONTRACT_STATE_DIR/local-task-runtime-state.json"

cat > "$CONTRACT_STATE_FILE" <<'CONTRACT_STATE'
{
  "schema": "dnyf.task.runtime.state.v1",
  "runtime_state": "ready",
  "next_sequence": 1,
  "queued": 0,
  "scheduled": 0,
  "running": 0,
  "completed": 0,
  "failed": 0,
  "retry_wait": 0,
  "cancelled": 0,
  "expired": 0,
  "dead_letter": 0,
  "execution_enabled": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "privilege_escalation": false
}
CONTRACT_STATE

chmod 600 "$CONTRACT_STATE_FILE"

export DNYF_TASK_CONTRACT_STATE="$CONTRACT_STATE_DIR"

TEST_OUTPUT="$(
  DNYF_TASK_CONTRACT_STATE="$CONTRACT_STATE_DIR"   node "$BIN" test 2>&1
)"


TEST_OUTPUT="$(
  node "$BIN" test 2>&1
)"

echo "$TEST_OUTPUT"

echo
echo "◆ Journal validation..."

VERIFY_OUTPUT="$(
  node "$BIN" verify 2>&1
)"

echo "$VERIFY_OUTPUT"

if ! printf '%s\n' "$VERIFY_OUTPUT" |
  grep -Fq '"ok": true'
then
  echo "[FAIL] task journal integrity"
  exit 1
fi

echo "[OK] task journal integrity"

echo
echo "◆ CLI validation..."

node "$BIN" status >/dev/null
echo "[OK] dnyf-task status"

node "$BIN" fingerprint >/dev/null
echo "[OK] dnyf-task fingerprint"

node "$BIN" schema >/dev/null
echo "[OK] dnyf-task schema"

node "$BIN" policy >/dev/null
echo "[OK] dnyf-task policy"

echo
echo "◆ Final status..."

node "$BIN" status

echo
echo "============================================================"
echo " PHASE 10 DNYF DISTRIBUTED TASK RUNTIME: PASS"
echo "============================================================"
echo
echo "Protocol : dnyf-task-runtime/1"
echo "Runtime  : ${RUNTIME#$ROOT/}"
echo "Policy   : ${ETC#$ROOT/}/dnyf-distributed-task-runtime-policy.json"
echo "Schema   : ${ETC#$ROOT/}/dnyf-distributed-task-runtime-schema.json"
echo "Registry : ${REGISTRY#$ROOT/}"
echo
echo "Execution remains disabled."
echo "Remote execution remains disabled."
echo "Remote installation remains disabled."
echo "Remote shell remains disabled."
echo "Privilege escalation remains disabled."
echo
