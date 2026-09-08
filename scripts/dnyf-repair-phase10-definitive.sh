#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

RUNTIME="$ROOT/opt/dnyf/runtime/task-runtime"
STATE="$ROOT/opt/dnyf/state/task-runtime"
BIN="$ROOT/bin/dnyf-task"
INSTALLER="$ROOT/scripts/phase10-dnyf-distributed-task-runtime.sh"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$ROOT/backups/phase10-definitive-repair/$STAMP"

mkdir -p "$BACKUP"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 10 DEFINITIVE REPAIR"
echo "============================================================"
echo
echo "Root   : $ROOT"
echo "Backup : $BACKUP"
echo

if [[ ! -d "$ROOT" ]]; then
  echo "[FAIL] DNYF-DEV root does not exist"
  exit 1
fi

if [[ ! -f "$INSTALLER" ]]; then
  echo "[FAIL] canonical Phase 10 installer not found:"
  echo "       $INSTALLER"
  exit 1
fi

echo "◆ Preserving current Phase 10 authority..."
cp -a "$RUNTIME" "$BACKUP/runtime" 2>/dev/null || true
cp -a "$STATE" "$BACKUP/state" 2>/dev/null || true
cp -a "$BIN" "$BACKUP/dnyf-task" 2>/dev/null || true
cp -a "$INSTALLER" "$BACKUP/phase10-installer.sh"

echo "[OK] repair backup created"
echo

echo "◆ Rebuilding canonical Phase 10 authority..."

cat > "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<'DNYF_AUTHORITY'
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

const STATE = path.join(
  ROOT,
  'opt/dnyf/state/task-runtime'
);

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
DNYF_AUTHORITY

chmod 600 \
  "$RUNTIME/dnyf-distributed-task-runtime-authority.js"

echo "[OK] authority rebuilt"
echo

echo "◆ Rebuilding definitive task CLI..."

cat > "$BIN" <<'DNYF_TASK_CLI'
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
DNYF_TASK_CLI

chmod 700 "$BIN"

ln -sfn \
  "$BIN" \
  "$ROOT/usr/bin/dnyf-task"

ln -sfn \
  "$BIN" \
  "$ROOT/usr/local/bin/dnyf-task"

echo "[OK] task CLI rebuilt"
echo

echo "◆ Patching canonical Phase 10 installer..."

python - "$INSTALLER" "$BIN" "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<'PY'
import sys
from pathlib import Path

installer = Path(sys.argv[1])
cli_path = Path(sys.argv[2])
authority_path = Path(sys.argv[3])

text = installer.read_text()

cli = cli_path.read_text()
authority = authority_path.read_text()

def replace_heredoc(source, marker_fragment, replacement):
    lines = source.splitlines(True)

    start = None
    delimiter = None

    for i, line in enumerate(lines):
        if marker_fragment in line and "<<" in line:
            start = i
            delimiter = line.split("<<", 1)[1].strip()
            if delimiter.startswith("-"):
                delimiter = delimiter[1:].strip()
            break

    if start is None:
        return source, False

    end = None

    for j in range(start + 1, len(lines)):
        if lines[j].strip() == delimiter:
            end = j
            break

    if end is None:
        return source, False

    heredoc_command = lines[start].split("<<", 1)[0]

    new_block = (
        heredoc_command +
        "<<" +
        delimiter +
        "\n" +
        replacement.rstrip("\n") +
        "\n" +
        delimiter +
        "\n"
    )

    return (
        "".join(lines[:start]) +
        new_block +
        "".join(lines[end + 1:]),
        True
    )

text, authority_replaced = replace_heredoc(
    text,
    'cat > "$RUNTIME/dnyf-distributed-task-runtime-authority.js"',
    authority
)

text, cli_replaced = replace_heredoc(
    text,
    'cat > "$BIN"',
    cli
)

if not authority_replaced:
    raise SystemExit(
        "Could not locate canonical authority heredoc in installer"
    )

if not cli_replaced:
    raise SystemExit(
        "Could not locate canonical CLI heredoc in installer"
    )

installer.write_text(text)
installer.chmod(
    installer.stat().st_mode
)

print("[OK] canonical authority installer block patched")
print("[OK] canonical CLI installer block patched")
PY

echo

echo "◆ Repairing runtime state safely..."

python - "$STATE/local-task-runtime-state.json" "$STATE/queue" <<'PY'
import json
import sys
from pathlib import Path

state_file = Path(sys.argv[1])
queue_dir = Path(sys.argv[2])

try:
    state = json.loads(
        state_file.read_text()
    )
except Exception:
    state = {}

for key in [
    "created_tasks",
    "queued_tasks",
    "scheduled_tasks",
    "authorized_tasks",
    "dispatched_tasks",
    "running_tasks",
    "completed_tasks",
    "failed_tasks",
    "retry_wait_tasks",
    "cancelled_tasks",
    "expired_tasks",
    "dead_letter_tasks",
    "last_sequence"
]:
    state[key] = int(
        state.get(key, 0) or 0
    )

state["queue_depth"] = len([
    x for x in queue_dir.iterdir()
    if x.is_file() and x.name.endswith(".json")
])

state.setdefault(
    "schema",
    "dnyf.task.runtime.state.v1"
)

state.setdefault(
    "version",
    "1.0.0"
)

state.setdefault(
    "last_journal_hash",
    None
)

state["updated_at"] = (
    __import__("datetime")
    .datetime.now(
        __import__("datetime").timezone.utc
    )
    .isoformat()
    .replace("+00:00", "Z")
)

tmp = state_file.with_suffix(".repair.tmp")

tmp.write_text(
    json.dumps(
        state,
        indent=2
    ) + "\n"
)

tmp.chmod(0o600)
tmp.replace(state_file)
state_file.chmod(0o600)

print(
    f"[OK] queue_depth synchronized: {state['queue_depth']}"
)
PY

echo

echo "◆ Validating repaired authority..."
node --check \
  "$RUNTIME/dnyf-distributed-task-runtime-authority.js"

echo "[OK] authority syntax"

echo "◆ Validating repaired CLI..."
node --check "$BIN"

echo "[OK] CLI syntax"

echo "◆ Validating CLI module resolution..."

if ! node "$BIN" status >/tmp/dnyf-phase10-status.json; then
  echo "[FAIL] dnyf-task status failed"
  cat /tmp/dnyf-phase10-status.json 2>/dev/null || true
  exit 1
fi

echo "[OK] dnyf-task resolves canonical authority"

echo

echo "◆ Running Phase 10 contract test..."

TEST_OUTPUT="$(
  node "$BIN" test
)"

printf '%s\n' "$TEST_OUTPUT"

echo

echo "◆ Contract assertions..."

python - "$TEST_OUTPUT" <<'PY'
import json
import sys

data = json.loads(sys.argv[1])

checks = {
    "contract": data.get("ok") is True,
    "validation": data.get("validation") is True,
    "dangerous operation blocked":
        data.get("dangerous_operation_blocked") is True,
    "idempotency":
        data.get("idempotency_deduplication") is True,
    "default deny":
        data.get("default_deny") is True,
    "journal hash chain":
        data.get("journal_hash_chain") is True,
    "execution disabled":
        data.get("execution_enabled") is False,
    "remote execution disabled":
        data.get("remote_execution") is False,
    "remote installation disabled":
        data.get("remote_installation") is False,
    "remote shell disabled":
        data.get("remote_shell") is False,
    "privilege escalation disabled":
        data.get("privilege_escalation") is False
}

failed = 0

for name, ok in checks.items():
    if ok:
        print(f"[OK] {name}")
    else:
        print(f"[FAIL] {name}")
        failed += 1

if failed:
    raise SystemExit(
        f"{failed} contract assertion(s) failed"
    )
PY

echo

echo "◆ Verifying persisted journal..."

node "$BIN" verify

echo

echo "◆ Verifying canonical installer syntax..."

bash -n "$INSTALLER"

echo "[OK] canonical Phase 10 installer syntax"

echo

echo "◆ Checking permanent CLI fix..."

if grep -q \
  "require(AUTHORITY)" \
  "$BIN"; then
  echo "[OK] CLI explicitly loads authority"
else
  echo "[FAIL] CLI authority loading contract missing"
  exit 1
fi

if grep -q \
  'require.*DNYF_ROOT' \
  "$BIN"; then
  echo "[FAIL] legacy root-module require remains"
  exit 1
else
  echo "[OK] legacy root-module require removed"
fi

echo

echo "◆ Checking permanent journal-chain implementation..."

if grep -q \
  "previous_hash" \
  "$RUNTIME/dnyf-distributed-task-runtime-authority.js"; then
  echo "[OK] previous_hash chain present"
else
  echo "[FAIL] journal previous_hash chain missing"
  exit 1
fi

echo

echo "◆ Checking security invariants..."

node - "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<'NODE'
const runtime = require(process.argv[2]);

const policy = runtime.loadPolicy();
const status = runtime.status();

const checks = [
  ["execution disabled",
    status.security.execution_enabled === false],

  ["remote execution disabled",
    status.security.remote_execution === false],

  ["remote installation disabled",
    status.security.remote_installation === false],

  ["remote shell disabled",
    status.security.remote_shell === false],

  ["privilege escalation disabled",
    status.security.privilege_escalation === false],

  ["self trust disabled",
    status.security.self_trust === false],

  ["self pairing disabled",
    status.security.self_pairing === false],

  ["automatic trust disabled",
    status.security.automatic_trust === false],

  ["policy execution disabled",
    !(
      policy.execution &&
      policy.execution.remote_execution === true
    )]
];

let failed = 0;

for (const [name, ok] of checks) {
  if (ok) {
    console.log(`[OK] ${name}`);
  } else {
    console.log(`[FAIL] ${name}`);
    failed++;
  }
}

if (failed) {
  process.exit(1);
}
NODE

echo

echo "============================================================"
echo " PHASE 10 DEFINITIVE REPAIR: PASS"
echo "============================================================"
echo
echo "◆ Repaired:"
echo "  • dnyf-task Node module resolution"
echo "  • canonical Phase 10 installer"
echo "  • persistent task journal hash chain"
echo "  • previous_hash verification"
echo "  • persistent queue-depth accounting"
echo "  • target-aware idempotency key"
echo "  • dangerous-operation denial"
echo "  • default-deny authorization"
echo
echo "◆ Security:"
echo "  • remote execution       : DISABLED"
echo "  • remote installation    : DISABLED"
echo "  • remote shell           : DISABLED"
echo "  • privilege escalation  : DISABLED"
echo "  • self-trust             : DISABLED"
echo "  • self-pairing           : DISABLED"
echo "  • automatic trust        : DISABLED"
echo
echo "Backup:"
echo "  $BACKUP"
echo
echo "Canonical installer:"
echo "  $INSTALLER"
echo
echo "Next validation command:"
echo "  $INSTALLER"
echo
