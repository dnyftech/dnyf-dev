#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
RUNTIME="$ROOT/opt/dnyf/runtime/universal"
IDENTITY_LOADER="$RUNTIME/dnyf-runtime-device-identity.js"
CORE="$RUNTIME/dnyf-runtime-core.js"
VALIDATOR="$RUNTIME/validation/dnyf-runtime-validator.sh"

CYAN=$'\033[1;36m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
RESET=$'\033[0m'

printf '\n'
printf '%b============================================================%b\n' "$CYAN" "$RESET"
printf '%b DNYF-DEV — PHASE 2 IDENTITY AUTHORITY REPAIR%b\n' "$CYAN" "$RESET"
printf '%b============================================================%b\n\n' "$CYAN" "$RESET"

[ -d "$ROOT" ] || {
    printf '%b[FAIL]%b DNYF-DEV root not found: %s\n' "$RED" "$ROOT"
    exit 1
}

[ -f "$IDENTITY_LOADER" ] || {
    printf '%b[FAIL]%b Runtime identity loader missing\n' "$RED" "$RESET"
    exit 1
}

###############################################################################
# Discover existing identity files.
#
# We NEVER create a new identity here.
###############################################################################

printf '%b◆ Searching existing DNYF identity authorities...%b\n' "$CYAN" "$RESET"

CANDIDATES=(
    "$ROOT/opt/dnyf/runtime/secure/identity/identity.json"
    "$ROOT/identity/identity.json"
    "$ROOT/etc/dnyf/identity/identity.json"
    "$ROOT/etc/dnyf/security/identity.json"
    "$ROOT/etc/dnyf/auth/identity.json"
    "$ROOT/opt/dnyf/config/identity.json"
    "$ROOT/opt/dnyf/config/dnyf-identity.json"
    "$ROOT/etc/dnyf/device-identity.json"
)

FOUND=""

for FILE in "${CANDIDATES[@]}"; do
    if [ -f "$FILE" ]; then
        if node - "$FILE" <<'DNYF_CHECK' >/dev/null 2>&1
const fs = require('fs');
const file = process.argv[2];

const data = JSON.parse(fs.readFileSync(file, 'utf8'));

if (!data || typeof data !== 'object') {
    process.exit(1);
}

if (!data.device_id) {
    process.exit(1);
}

process.exit(0);
DNYF_CHECK
        then
            FOUND="$FILE"
            break
        fi
    fi
done

###############################################################################
# Broader discovery only if canonical candidates did not work.
###############################################################################

if [ -z "$FOUND" ]; then
    printf '%b[INFO]%b Canonical identity locations did not contain a usable identity.\n' \
        "$YELLOW" "$RESET"

    while IFS= read -r FILE; do
        if node - "$FILE" <<'DNYF_CHECK' >/dev/null 2>&1
const fs = require('fs');
const file = process.argv[2];

try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));

    if (
        data &&
        typeof data === 'object' &&
        typeof data.device_id === 'string' &&
        data.device_id.trim().length > 0
    ) {
        process.exit(0);
    }
} catch (_) {}

process.exit(1);
DNYF_CHECK
        then
            FOUND="$FILE"
            break
        fi
    done < <(
        find "$ROOT" \
            -type f \
            \( -name '*identity*.json' -o -name 'identity.json' \) \
            -not -path '*/node_modules/*' \
            -not -path '*/.git/*' \
            2>/dev/null
    )
fi

if [ -z "$FOUND" ]; then
    printf '%b[FAIL]%b No existing DNYF identity authority was found.\n' \
        "$RED" "$RESET"

    printf '\n'
    printf '%bNo identity was generated or modified.%b\n' \
        "$YELLOW" "$RESET"

    exit 1
fi

printf '%b[OK]%b Existing identity authority found:\n' "$GREEN" "$RESET"
printf '     %s\n' "$FOUND"

###############################################################################
# Validate identity structure.
###############################################################################

export DNYF_ROOT="$ROOT"
export DNYF_IDENTITY_FILE="$FOUND"

IDENTITY_JSON="$(node - "$FOUND" <<'DNYF_IDENTITY'
const fs = require('fs');

const file = process.argv[2];
const data = JSON.parse(fs.readFileSync(file, 'utf8'));

const required = ['device_id'];

for (const field of required) {
    if (!data[field]) {
        throw new Error(`Missing required identity field: ${field}`);
    }
}

const result = {
    device_id: String(data.device_id).toLowerCase(),
    fingerprint: data.fingerprint
        ? String(data.fingerprint).toLowerCase()
        : null,
    public_key: data.public_key || null,
    algorithm: data.algorithm || 'Ed25519',
    source: file
};

process.stdout.write(JSON.stringify(result));
DNYF_IDENTITY
)"

DEVICE_ID="$(printf '%s' "$IDENTITY_JSON" | node -e '
let s="";
process.stdin.on("data",d=>s+=d);
process.stdin.on("end",()=>{
  const x=JSON.parse(s);
  process.stdout.write(x.device_id);
});
')"

FINGERPRINT="$(printf '%s' "$IDENTITY_JSON" | node -e '
let s="";
process.stdin.on("data",d=>s+=d);
process.stdin.on("end",()=>{
  const x=JSON.parse(s);
  process.stdout.write(x.fingerprint || "");
});
')"

printf '%b[OK]%b device ID: %s\n' "$GREEN" "$RESET" "$DEVICE_ID"

if [ -n "$FINGERPRINT" ]; then
    printf '%b[OK]%b fingerprint: %s\n' \
        "$GREEN" "$RESET" "$FINGERPRINT"
else
    printf '%b[WARN]%b identity has no fingerprint field\n' \
        "$YELLOW" "$RESET"
fi

###############################################################################
# Install authoritative loader.
###############################################################################

cat > "$IDENTITY_LOADER" <<'DNYF_IDENTITY_LOADER'
'use strict';

const fs = require('fs');
const path = require('path');

function resolveRoot() {
    return process.env.DNYF_ROOT ||
        path.resolve(__dirname, '../../../../..');
}

function candidateIdentityFiles() {
    const root = resolveRoot();

    return [
        process.env.DNYF_IDENTITY_FILE,

        path.join(
            root,
            'opt/dnyf/runtime/secure/identity/identity.json'
        ),

        path.join(
            root,
            'identity/identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/identity/identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/security/identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/auth/identity.json'
        ),

        path.join(
            root,
            'opt/dnyf/config/identity.json'
        ),

        path.join(
            root,
            'opt/dnyf/config/dnyf-identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/device-identity.json'
        )
    ].filter(Boolean);
}

function readIdentity(file) {
    const data = JSON.parse(
        fs.readFileSync(file, 'utf8')
    );

    if (
        !data ||
        typeof data !== 'object' ||
        typeof data.device_id !== 'string' ||
        data.device_id.trim() === ''
    ) {
        throw new Error(
            `Invalid DNYF identity authority: ${file}`
        );
    }

    return {
        device_id: String(data.device_id)
            .trim()
            .toLowerCase(),

        fingerprint: data.fingerprint
            ? String(data.fingerprint)
                .trim()
                .toLowerCase()
            : null,

        public_key: data.public_key || null,

        algorithm: data.algorithm || 'Ed25519',

        source: file
    };
}

function loadIdentity() {
    const candidates = candidateIdentityFiles();

    const errors = [];

    for (const file of candidates) {
        try {
            if (!fs.existsSync(file)) {
                continue;
            }

            return readIdentity(file);
        } catch (error) {
            errors.push(
                `${file}: ${error.message}`
            );
        }
    }

    const detail = errors.length
        ? `\n${errors.join('\n')}`
        : '';

    throw new Error(
        'DNYF canonical cryptographic identity could not be loaded.' +
        detail
    );
}

if (require.main === module) {
    process.stdout.write(
        JSON.stringify(loadIdentity(), null, 2) + '\n'
    );
}

module.exports = {
    resolveRoot,
    candidateIdentityFiles,
    loadIdentity
};
DNYF_IDENTITY_LOADER

chmod 0644 "$IDENTITY_LOADER"

###############################################################################
# Establish explicit runtime identity authority.
###############################################################################

mkdir -p "$ROOT/etc/dnyf/runtime"

cat > "$ROOT/etc/dnyf/runtime/dnyf-runtime-identity-authority.json" <<DNYF_AUTHORITY
{
  "schema": "dnyf.runtime.identity.authority.v1",
  "authority": "existing-canonical-identity",
  "identity_file": "$FOUND",
  "device_id": "$DEVICE_ID",
  "fingerprint": "$FINGERPRINT",
  "algorithm": "Ed25519",
  "create_missing_identity": false,
  "replace_existing_identity": false,
  "generate_new_identity": false
}
DNYF_AUTHORITY

###############################################################################
# Verify loader directly.
###############################################################################

printf '\n%b◆ Testing canonical identity loader...%b\n' "$CYAN" "$RESET"

IDENTITY_RESULT="$(
    DNYF_ROOT="$ROOT" \
    DNYF_IDENTITY_FILE="$FOUND" \
    node "$IDENTITY_LOADER"
)"

printf '%s\n' "$IDENTITY_RESULT"

printf '%s\n' "$IDENTITY_RESULT" |
    grep -q "\"device_id\": \"$DEVICE_ID\""

printf '%b[OK]%b canonical identity loader\n' "$GREEN" "$RESET"

###############################################################################
# Test runtime core.
###############################################################################

printf '\n%b◆ Testing universal runtime core...%b\n' "$CYAN" "$RESET"

RUNTIME_RESULT="$(
    DNYF_ROOT="$ROOT" \
    DNYF_IDENTITY_FILE="$FOUND" \
    node "$CORE"
)"

printf '%s\n' "$RUNTIME_RESULT" | head -40

printf '%s\n' "$RUNTIME_RESULT" |
    grep -q '"runtime": "dnyf-universal-runtime/1"'

printf '%s\n' "$RUNTIME_RESULT" |
    grep -q "\"device_id\": \"$DEVICE_ID\""

printf '%b[OK]%b universal runtime identity integration\n' \
    "$GREEN" "$RESET"

###############################################################################
# Security invariants.
###############################################################################

printf '\n%b◆ Checking security invariants...%b\n' "$CYAN" "$RESET"

for FLAG in \
    remote_execution \
    remote_installation \
    remote_shell \
    self_trust \
    self_pairing \
    automatic_trust
do
    printf '%s\n' "$RUNTIME_RESULT" |
        grep -q "\"$FLAG\": false"

    printf '%b[OK]%b %s disabled\n' \
        "$GREEN" "$RESET" "$FLAG"
done

###############################################################################
# Final validator.
###############################################################################

printf '\n%b◆ Running complete Phase 2 validator...%b\n\n' \
    "$CYAN" "$RESET"

DNYF_ROOT="$ROOT" \
DNYF_IDENTITY_FILE="$FOUND" \
"$VALIDATOR"

printf '\n'
printf '%b============================================================%b\n' \
    "$GREEN" "$RESET"
printf '%b DNYFTECH IDENTITY AUTHORITY REPAIR: PASS%b\n' \
    "$GREEN" "$RESET"
printf '%b============================================================%b\n' \
    "$GREEN" "$RESET"

printf '\n'
printf '%bCanonical identity:%b %s\n' \
    "$CYAN" "$RESET" "$FOUND"

printf '%bDevice ID:%b %s\n' \
    "$CYAN" "$RESET" "$DEVICE_ID"

[ -n "$FINGERPRINT" ] && \
printf '%bFingerprint:%b %s\n' \
    "$CYAN" "$RESET" "$FINGERPRINT"

printf '\n'
printf '%bNo new identity was generated.%b\n' \
    "$GREEN" "$RESET"

printf '%bExisting cryptographic identity remains authoritative.%b\n' \
    "$GREEN" "$RESET"

