#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

INSTALLER="$ROOT/scripts/phase10-dnyf-distributed-task-runtime.sh"
STATE="$ROOT/opt/dnyf/state/task-runtime"
BACKUP="$ROOT/backups/phase10-contract-state/$(date -u +%Y%m%dT%H%M%SZ)"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 10 CONTRACT STATE REPAIR"
echo "============================================================"
echo
echo "Root      : $ROOT"
echo "Installer : $INSTALLER"
echo "State     : $STATE"
echo "Backup    : $BACKUP"
echo

mkdir -p "$BACKUP"

cp -a "$INSTALLER" "$BACKUP/phase10-dnyf-distributed-task-runtime.sh"

echo "[OK] installer backup created"

echo
echo "◆ Inspecting contract validation..."

MATCH_LINE="$(
  grep -nF 'dnyf-task test' "$INSTALLER" |
  head -1 |
  cut -d: -f1 || true
)"

if [ -z "$MATCH_LINE" ]; then
  echo "[FAIL] could not locate dnyf-task test invocation"
  exit 1
fi

echo "[OK] contract test invocation located at line $MATCH_LINE"

echo
echo "◆ Checking current state/journal relationship..."

node - "$STATE/local-task-runtime-state.json" "$STATE/journal" <<'NODE'
const fs = require('fs');
const path = require('path');

const stateFile = process.argv[2];
const journalDir = process.argv[3];

const state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));

let records = [];

if (fs.existsSync(journalDir)) {
  for (const name of fs.readdirSync(journalDir).sort()) {
    const file = path.join(journalDir, name);

    if (!fs.statSync(file).isFile()) continue;

    const text = fs.readFileSync(file, 'utf8').trim();

    if (!text) continue;

    for (const line of text.split(/\r?\n/)) {
      if (!line.trim()) continue;

      try {
        records.push(JSON.parse(line));
      } catch {
        // Ignore unrelated non-JSON files during inspection.
      }
    }
  }
}

const lastSequence =
  records.length > 0
    ? Math.max(
        ...records
          .map(r => Number(r.sequence))
          .filter(Number.isFinite)
      )
    : 0;

console.log(JSON.stringify({
  state_next_sequence: state.next_sequence,
  journal_records: records.length,
  journal_last_sequence: lastSequence,
  consistent:
    Number(state.next_sequence) === lastSequence + 1
}, null, 2));
NODE

echo
echo "◆ Backing up existing task-runtime state..."

cp -a "$STATE" "$BACKUP/state-before-reset"

echo "[OK] existing task-runtime state preserved"

echo
echo "◆ Locating canonical state initialization..."

if ! grep -Fq '"next_sequence": 1' \
  "$INSTALLER"
then
  echo "[FAIL] canonical initial next_sequence=1 state was not found"
  exit 1
fi

echo "[OK] canonical fresh-state initialization confirmed"

echo
echo "◆ Patching canonical installer to isolate contract state..."

python3 - "$INSTALLER" <<'PY'
from pathlib import Path
import sys

installer = Path(sys.argv[1])
text = installer.read_text()

needle = '''echo "◆ Task runtime contract validation..."
'''

if needle not in text:
    raise SystemExit(
        "[FAIL] contract validation heading not found"
    )

replacement = '''echo "◆ Task runtime contract validation..."

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

mkdir -p \
  "$CONTRACT_JOURNAL_DIR" \
  "$CONTRACT_QUEUE_DIR" \
  "$CONTRACT_DEDUPE_DIR" \
  "$CONTRACT_REPLAY_DIR" \
  "$CONTRACT_DEADLETTER_DIR" \
  "$CONTRACT_AUDIT_DIR" \
  "$CONTRACT_CHECKPOINT_DIR" \
  "$CONTRACT_RESULTS_DIR" \
  "$CONTRACT_LOCK_DIR"

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
  DNYF_TASK_CONTRACT_STATE="$CONTRACT_STATE_DIR" \
  node "$BIN" test 2>&1
)"

'''

text = text.replace(needle, replacement, 1)

installer.write_text(text)
PY

echo "[OK] isolated contract state block installed"

echo
echo "◆ Verifying contract isolation..."

grep -Fq 'CONTRACT_STATE_DIR="$STATE/contract-validation"' "$INSTALLER"
grep -Fq 'DNYF_TASK_CONTRACT_STATE="$CONTRACT_STATE_DIR"' "$INSTALLER"
grep -Fq 'node "$BIN" test' "$INSTALLER"

echo "[OK] contract state isolation persists"

echo
echo "◆ Checking authority support for isolated state..."

AUTHORITY="$ROOT/opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js"

if ! grep -Fq 'DNYF_TASK_CONTRACT_STATE' "$AUTHORITY"; then
  echo "[WARN] authority does not expose contract-state override"
  echo
  echo "The installer must therefore use a temporary working root."
  echo
fi

echo
echo "◆ Shell syntax validation..."

bash -n "$INSTALLER"

echo "[OK] installer shell syntax"

echo
echo "◆ Showing repaired contract section..."

awk '
/echo "◆ Task runtime contract validation\.\.\."/ {
    show=1
}
show {
    print
    count++
}
show && count >= 55 {
    exit
}
' "$INSTALLER"

echo
echo "============================================================"
echo " PHASE 10 CONTRACT STATE REPAIR: PASS"
echo "============================================================"
echo
echo "Backup: $BACKUP"
echo
echo "IMPORTANT:"
echo "The contract validator must not mix stale journal records"
echo "with a freshly initialized task-runtime state."
echo
echo "Next: run the canonical Phase 10 installer."
echo
