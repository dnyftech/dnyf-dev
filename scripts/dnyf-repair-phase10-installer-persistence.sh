#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

INSTALLER="$ROOT/scripts/phase10-dnyf-distributed-task-runtime.sh"
AUTHORITY="$ROOT/opt/dnyf/runtime/task-runtime/dnyf-distributed-task-runtime-authority.js"
CLI="$ROOT/bin/dnyf-task"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$ROOT/backups/phase10-installer-persistence/$STAMP"

echo "============================================================"
echo " DNYFTECH — PHASE 10 INSTALLER PERSISTENCE REPAIR"
echo "============================================================"
echo
echo "Root      : $ROOT"
echo "Installer : $INSTALLER"
echo "Authority : $AUTHORITY"
echo "CLI       : $CLI"
echo "Backup    : $BACKUP_DIR"
echo

###############################################################################
# 1. PRECONDITIONS
###############################################################################

test -f "$INSTALLER"
test -f "$AUTHORITY"
test -f "$CLI"

mkdir -p "$BACKUP_DIR"

cp -p "$INSTALLER" "$BACKUP_DIR/phase10-dnyf-distributed-task-runtime.sh"
cp -p "$AUTHORITY" "$BACKUP_DIR/dnyf-distributed-task-runtime-authority.js"
cp -p "$CLI" "$BACKUP_DIR/dnyf-task"

echo "[OK] persistence-repair backup created"

###############################################################################
# 2. VERIFY LIVE REPAIRED AUTHORITY
###############################################################################

echo
echo "◆ Verifying live repaired authority..."

node --check "$AUTHORITY"

grep -Fq "const ENV_ROOT = process.env.DNYF_ROOT;" "$AUTHORITY"
grep -Fq "const LOCAL_ROOT = path.resolve(__dirname, '../../../..');" "$AUTHORITY"
grep -Fq "endsWith('/DNYF-DEV')" "$AUTHORITY"

if grep -Fq "require('/data/data/com.termux/files/home/DNYF-DEV')" "$AUTHORITY"; then
  echo "[FAIL] bad hardcoded DNYF-DEV require found in authority"
  exit 1
fi

echo "[OK] authority syntax"
echo "[OK] authority root resolution"
echo "[OK] authority has no hardcoded DNYF-DEV require"

###############################################################################
# 3. VERIFY LIVE REPAIRED CLI
###############################################################################

echo
echo "◆ Verifying live repaired task CLI..."

node --check "$CLI"

grep -Fq "dnyf-distributed-task-runtime-authority.js" "$CLI"

if grep -Fq "require('/data/data/com.termux/files/home/DNYF-DEV')" "$CLI"; then
  echo "[FAIL] bad hardcoded DNYF-DEV require found in CLI"
  exit 1
fi

if grep -Fq "require(process.env.DNYF_ROOT ||" "$CLI"; then
  echo "[FAIL] unsafe CLI require fallback remains"
  exit 1
fi

echo "[OK] CLI syntax"
echo "[OK] CLI points directly to task authority"
echo "[OK] CLI has no hardcoded DNYF-DEV require"
echo "[OK] CLI has no unsafe DNYF_ROOT require fallback"

###############################################################################
# 4. PATCH INSTALLER FROM LIVE REPAIRED FILES
###############################################################################

echo
echo "◆ Patching canonical installer from verified live sources..."

python - "$INSTALLER" "$AUTHORITY" "$CLI" <<'PY'
import sys
from pathlib import Path

installer_path = Path(sys.argv[1])
authority_path = Path(sys.argv[2])
cli_path = Path(sys.argv[3])

text = installer_path.read_text()
authority = authority_path.read_text()
cli = cli_path.read_text()

lines = text.splitlines(keepends=True)

def patch_heredoc(lines, marker, delimiter, replacement):
    start = None

    for i, line in enumerate(lines):
        if line.rstrip("\n") == marker:
            start = i
            break

    if start is None:
        raise SystemExit(
            f"Could not locate installer heredoc start: {marker}"
        )

    end = None

    for i in range(start + 1, len(lines)):
        if lines[i].rstrip("\n") == delimiter:
            end = i
            break

    if end is None:
        raise SystemExit(
            f"Could not locate heredoc terminator {delimiter!r} "
            f"after: {marker}"
        )

    replacement_lines = replacement.splitlines(keepends=True)

    if replacement and not replacement.endswith("\n"):
        replacement_lines.append("\n")

    return (
        lines[:start + 1]
        + replacement_lines
        + lines[end:]
    )

authority_marker = (
    'cat > "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<\'JS\''
)

cli_marker = (
    'cat > "$BIN" <<\'JS\''
)

lines = patch_heredoc(
    lines,
    authority_marker,
    "JS",
    authority,
)

lines = patch_heredoc(
    lines,
    cli_marker,
    "JS",
    cli,
)

new_text = "".join(lines)
installer_path.write_text(new_text)

print("[OK] canonical authority heredoc replaced")
print("[OK] canonical CLI heredoc replaced")
PY

###############################################################################
# 5. VERIFY INSTALLER PATCH
###############################################################################

echo
echo "◆ Verifying canonical installer persistence..."

node --check "$AUTHORITY"
node --check "$CLI"

grep -Fq \
  'cat > "$RUNTIME/dnyf-distributed-task-runtime-authority.js" <<'\''JS'\''' \
  "$INSTALLER"

grep -Fq \
  'cat > "$BIN" <<'\''JS'\''' \
  "$INSTALLER"

grep -Fq \
  "const ENV_ROOT = process.env.DNYF_ROOT;" \
  "$INSTALLER"

grep -Fq \
  "const LOCAL_ROOT = path.resolve(__dirname, '../../../..');" \
  "$INSTALLER"

grep -Fq \
  "endsWith('/DNYF-DEV')" \
  "$INSTALLER"

grep -Fq \
  "dnyf-distributed-task-runtime-authority.js" \
  "$INSTALLER"

if grep -Fq \
  "require('/data/data/com.termux/files/home/DNYF-DEV')" \
  "$INSTALLER"
then
  echo "[FAIL] installer still contains hardcoded DNYF-DEV require"
  exit 1
fi

if grep -Fq \
  "require(process.env.DNYF_ROOT ||" \
  "$INSTALLER"
then
  echo "[FAIL] installer still contains unsafe CLI require fallback"
  exit 1
fi

echo "[OK] authority heredoc persists"
echo "[OK] CLI heredoc persists"
echo "[OK] root-resolution logic persists"
echo "[OK] unsafe root require absent"

###############################################################################
# 6. INSTALLER SYNTAX
###############################################################################

echo
echo "◆ Validating installer shell syntax..."

bash -n "$INSTALLER"

echo "[OK] canonical Phase 10 installer syntax"

###############################################################################
# 7. SHOW PATCHED LOCATIONS
###############################################################################

echo
echo "◆ Patched authority root section..."

sed -n '266,285p' "$INSTALLER"

echo
echo "◆ Patched CLI authority section..."

sed -n '1151,1170p' "$INSTALLER"

###############################################################################
# 8. LIVE AUTHORITY CONTRACT
###############################################################################

echo
echo "◆ Testing repaired live task runtime..."

node "$CLI" status

echo
node "$CLI" test

echo
echo "◆ Verifying task journal..."

node "$CLI" verify

###############################################################################
# 9. FINAL PERSISTENCE CHECK
###############################################################################

echo
echo "◆ Final persistence checks..."

grep -Fq \
  "const ENV_ROOT = process.env.DNYF_ROOT;" \
  "$INSTALLER"

grep -Fq \
  "const LOCAL_ROOT = path.resolve(__dirname, '../../../..');" \
  "$INSTALLER"

grep -Fq \
  "dnyf-distributed-task-runtime-authority.js" \
  "$INSTALLER"

if grep -Fq \
  "require('/data/data/com.termux/files/home/DNYF-DEV')" \
  "$INSTALLER"
then
  echo "[FAIL] final installer contains forbidden hardcoded require"
  exit 1
fi

if grep -Fq \
  "require(process.env.DNYF_ROOT ||" \
  "$INSTALLER"
then
  echo "[FAIL] final installer contains unsafe CLI require"
  exit 1
fi

echo "[OK] canonical installer permanently contains repaired authority"
echo "[OK] canonical installer permanently contains repaired CLI"
echo "[OK] canonical installer root handling is valid"
echo "[OK] forbidden hardcoded root require absent"
echo "[OK] unsafe CLI fallback absent"

echo
echo "============================================================"
echo " PHASE 10 INSTALLER PERSISTENCE REPAIR: PASS"
echo "============================================================"
echo
echo "The canonical installer can now safely be executed."
echo "Backup: $BACKUP_DIR"
echo
