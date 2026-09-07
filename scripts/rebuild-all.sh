#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

echo
echo "============================================================"
echo " DNYF-DEV MASTER REBUILD"
echo "============================================================"

for phase in \
    phase2 \
    phase3 \
    phase4 \
    phase5 \
    phase6 \
    phase7 \
    phase8
do
    SCRIPT="$ROOT/scripts/$phase/install.sh"

    if [ -x "$SCRIPT" ]; then
        echo
        echo "[RUN] $phase"
        DNYF_ROOT="$ROOT" "$SCRIPT"
    else
        echo "[INFO] $phase installer not yet generated"
    fi
done

echo
echo "[DONE] Master rebuild sequence finished."
echo "[NEXT] Run: $ROOT/scripts/validate.sh"
