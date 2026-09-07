#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT="$HOME/DNYF-DEV"

echo "============================================================"
echo " DNYFTECH — CRYPTOGRAPHIC AUTHORITY RECOVERY SEARCH"
echo "============================================================"
echo
echo "Canonical device:"
echo "  cbd06be57a51cb84e12b4e112a4d06e9"
echo
echo "Historical fingerprint:"
echo "  3b3cab3fec13f87ff4039d06851c0faeb8d968159cce88e7cde890c69bc539c9"
echo

echo "◆ Searching Termux home and DNYF-DEV..."
echo "------------------------------------------------------------"

find "$HOME" \
    -type f \
    \( \
      -name 'device-ed25519-private.pem' -o \
      -name 'device-ed25519-public.pem' -o \
      -name 'identity.json' -o \
      -name '*identity*.json' -o \
      -name '*ed25519*.pem' -o \
      -name '*cryptauth*.json' -o \
      -name '*cryptographic*.json' -o \
      -name '*trust*.json' \
    \) \
    ! -path '*/node_modules/*' \
    ! -path '*/.git/*' \
    ! -path "$ROOT/*" \
    -print 2>/dev/null | sort

echo
echo "◆ Searching Android shared storage..."
echo "------------------------------------------------------------"

if [ -d "$HOME/storage/shared" ]; then
    find "$HOME/storage/shared" \
        -type f \
        \( \
          -name 'device-ed25519-private.pem' -o \
          -name 'device-ed25519-public.pem' -o \
          -name 'identity.json' -o \
          -name '*identity*.json' -o \
          -name '*ed25519*.pem' -o \
          -name '*cryptauth*.json' -o \
          -name '*cryptographic*.json' -o \
          -name '*.zip' -o \
          -name '*.tar.gz' -o \
          -name '*.tgz' \
        \) \
        -print 2>/dev/null | sort
else
    echo "[INFO] Android shared storage is not mounted."
fi

echo
echo "◆ Searching archives for cryptographic authority names..."
echo "------------------------------------------------------------"

if command -v unzip >/dev/null 2>&1; then
    find "$HOME/storage/shared" "$HOME" \
        -type f \
        \( -name '*.zip' -o -name '*.tar.gz' -o -name '*.tgz' \) \
        ! -path "$ROOT/*" \
        -print 2>/dev/null |
    while IFS= read -r archive; do
        echo
        echo "===== $archive ====="

        case "$archive" in
            *.zip)
                unzip -l "$archive" 2>/dev/null |
                grep -Ei \
                  'identity|ed25519|cryptauth|device.*key|public.*key|private.*key' \
                  || true
                ;;
            *.tar.gz|*.tgz)
                tar -tzf "$archive" 2>/dev/null |
                grep -Ei \
                  'identity|ed25519|cryptauth|device.*key|public.*key|private.*key' \
                  || true
                ;;
        esac
    done
else
    echo "[WARN] unzip is not installed; ZIP inspection skipped."
fi

echo
echo "◆ Searching for the historical fingerprint..."
echo "------------------------------------------------------------"

grep -RIl \
    '3b3cab3fec13f87ff4039d06851c0faeb8d968159cce88e7cde890c69bc539c9' \
    "$HOME" \
    "$HOME/storage/shared" \
    2>/dev/null |
    grep -v '/node_modules/' |
    grep -v '/.git/' |
    head -200 || true

echo
echo "◆ Searching for canonical device ID..."
echo "------------------------------------------------------------"

grep -RIl \
    'cbd06be57a51cb84e12b4e112a4d06e9' \
    "$HOME" \
    "$HOME/storage/shared" \
    2>/dev/null |
    grep -v '/node_modules/' |
    grep -v '/.git/' |
    head -200 || true

echo
echo "============================================================"
echo " RECOVERY SEARCH COMPLETE"
echo "============================================================"
echo
echo "IMPORTANT:"
echo "No files were created, modified, deleted, or regenerated."
