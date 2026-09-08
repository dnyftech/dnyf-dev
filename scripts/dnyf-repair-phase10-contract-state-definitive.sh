#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

AUTHORITY="$ROOT/opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js"
CLI="$ROOT/bin/dnyf-task"
INSTALLER="$ROOT/scripts/phase10-dnyf-distributed-task-runtime.sh"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP="$ROOT/backups/phase10-contract-state-definitive/$STAMP"

mkdir -p "$BACKUP"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 10 DEFINITIVE CONTRACT STATE REPAIR"
echo "============================================================"
echo
echo "Root      : $ROOT"
echo "Authority : $AUTHORITY"
echo "CLI       : $CLI"
echo "Installer : $INSTALLER"
echo "Backup    : $BACKUP"
echo

cp -a "$AUTHORITY" "$BACKUP/dnyf-distributed-task-runtime-authority.js"
cp -a "$CLI" "$BACKUP/dnyf-task"
cp -a "$INSTALLER" "$BACKUP/phase10-dnyf-distributed-task-runtime.sh"

echo "[OK] repair backups created"

echo
echo "◆ Inspecting canonical authority state-path implementation..."

sed -n '1,95p' "$AUTHORITY"

echo
echo "◆ Patching authority state-path resolution..."

python3 - "$AUTHORITY" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text()

old = """const STATE = path.join(
  ROOT,
  'opt/dnyf/state/task-runtime'
);
"""

new = """/*
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
"""

if old not in text:
    raise SystemExit(
        "[FAIL] canonical STATE declaration not found"
    )

text = text.replace(old, new, 1)

p.write_text(text)
PY

chmod 600 "$AUTHORITY"

echo "[OK] authority state-path override installed"

echo
echo "◆ Validating authority syntax..."

node --check "$AUTHORITY"

echo "[OK] authority syntax"

echo
echo "◆ Verifying isolated-state support..."

grep -Fq 'DNYF_TASK_CONTRACT_STATE' "$AUTHORITY"
grep -Fq 'CANONICAL_STATE' "$AUTHORITY"
grep -Fq "path.isAbsolute(CONTRACT_STATE)" "$AUTHORITY"

echo "[OK] contract-state support confirmed"

echo
echo "◆ Testing production-state default..."

DNYF_TASK_CONTRACT_STATE="" node - <<'NODE'
const a = require(
  process.env.DNYF_ROOT +
  '/opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js'
);

if (!a.ROOT.endsWith('/DNYF-DEV')) {
  throw new Error('invalid_root');
}

console.log('[OK] production authority root');
NODE

echo
echo "◆ Creating isolated contract state..."

CONTRACT="$ROOT/opt/dnyf/state/task-runtime/contract-validation"

rm -rf "$CONTRACT"

mkdir -p \
  "$CONTRACT/journal" \
  "$CONTRACT/queue" \
  "$CONTRACT/dedupe" \
  "$CONTRACT/replay" \
  "$CONTRACT/dead-letter" \
  "$CONTRACT/audit" \
  "$CONTRACT/checkpoints" \
  "$CONTRACT/results" \
  "$CONTRACT/locks"

cat > "$CONTRACT/local-task-runtime-state.json" <<'JSON'
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

chmod 600 "$CONTRACT/local-task-runtime-state.json"

echo "[OK] isolated contract state initialized"

echo
echo "◆ Testing authority against isolated state..."

CONTRACT_OUTPUT="$(
  DNYF_TASK_CONTRACT_STATE="$CONTRACT" \
  node - <<'NODE'
const a = require(
  process.env.DNYF_ROOT +
  '/opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js'
);

const s = a.status();

if (s.state.next_sequence !== 1) {
  throw new Error(
    'unexpected_contract_sequence:' +
    s.state.next_sequence
  );
}

if (s.journal.records !== 0) {
  throw new Error(
    'unexpected_contract_journal:' +
    s.journal.records
  );
}

console.log(JSON.stringify({
  root: s.root,
  next_sequence: s.state.next_sequence,
  journal_records: s.journal.records,
  journal_last_sequence: s.journal.last_sequence
}, null, 2));
NODE
)"

printf '%s\n' "$CONTRACT_OUTPUT"

echo "[OK] authority honors isolated contract state"

echo
echo "◆ Testing CLI against isolated state..."

CLI_OUTPUT="$(
  DNYF_TASK_CONTRACT_STATE="$CONTRACT" \
  node "$CLI" test 2>&1
)"

printf '%s\n' "$CLI_OUTPUT"

if ! printf '%s\n' "$CLI_OUTPUT" |
  grep -Fq '"ok": true'
then
  echo "[FAIL] isolated CLI contract test did not pass"
  exit 1
fi

echo "[OK] isolated CLI contract test"

echo
echo "◆ Patching canonical installer authority persistence..."

python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
text = p.read_text()

start = 'cat > "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<\'JS\''
end = '\nJS\n'

i = text.find(start)

if i < 0:
    raise SystemExit("[FAIL] authority heredoc marker not found")

body_start = i + len(start)

j = text.find(end, body_start)

if j < 0:
    raise SystemExit("[FAIL] authority heredoc terminator not found")

authority = Path(
    p.parent.parent /
    "opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js"
).read_text()

replacement = (
    start +
    "\n" +
    authority.rstrip("\n") +
    "\nJS"
)

text = text[:i] + replacement + text[j + len(end):]

p.write_text(text)
PY

echo "[OK] canonical installer authority synchronized"

echo
echo "◆ Verifying installer contains contract-state support..."

grep -Fq 'DNYF_TASK_CONTRACT_STATE' "$INSTALLER"
grep -Fq 'CANONICAL_STATE' "$INSTALLER"
grep -Fq 'path.isAbsolute(CONTRACT_STATE)' "$INSTALLER"

echo "[OK] installer persists contract-state support"

echo
echo "◆ Verifying installer CLI contract isolation..."

grep -Fq 'CONTRACT_STATE_DIR="$STATE/contract-validation"' "$INSTALLER"
grep -Fq 'DNYF_TASK_CONTRACT_STATE="$CONTRACT_STATE_DIR"' "$INSTALLER"

echo "[OK] installer contract isolation confirmed"

echo
echo "◆ Shell syntax validation..."

bash -n "$INSTALLER"

echo "[OK] canonical installer syntax"

echo
echo "◆ Final live production-state verification..."

node "$CLI" status

echo
echo "◆ Final live contract verification..."

DNYF_TASK_CONTRACT_STATE="$CONTRACT" \
node "$CLI" test

echo
echo "◆ Final authority security verification..."

node - "$AUTHORITY" <<'NODE'
const a = require(process.argv[2]);

const s = a.status();

const checks = {
  execution_enabled: s.security.execution_enabled === false,
  remote_execution: s.security.remote_execution === false,
  remote_installation: s.security.remote_installation === false,
  remote_shell: s.security.remote_shell === false,
  privilege_escalation: s.security.privilege_escalation === false,
  self_trust: s.security.self_trust === false,
  self_pairing: s.security.self_pairing === false,
  automatic_trust: s.security.automatic_trust === false
};

for (const [name, ok] of Object.entries(checks)) {
  if (!ok) {
    throw new Error('security_invariant_failed:' + name);
  }

  console.log('[OK] ' + name);
}
NODE

echo
echo "============================================================"
echo " PHASE 10 DEFINITIVE CONTRACT STATE REPAIR: PASS"
echo "============================================================"
echo
echo "Backup: $BACKUP"
echo
echo "The runtime now supports:"
echo "  • canonical production state by default"
echo "  • isolated contract-validation state"
echo "  • sequence-safe journal validation"
echo "  • persistent hash-chain validation"
echo "  • no arbitrary state-path redirection"
echo
echo "Next: execute the canonical Phase 10 installer."
echo
