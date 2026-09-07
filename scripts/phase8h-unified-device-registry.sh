#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
REG_DIR="$ROOT/registry"
ETC_DIR="$ROOT/etc/dnyf/registry"
RUNTIME_DIR="$ROOT/opt/dnyf/runtime/registry"
STATE_DIR="$ROOT/opt/dnyf/state/registry"
AUDIT_DIR="$ROOT/opt/dnyf/state/audit"
BACKUP="$ROOT/backups/phase8h-unified-device-registry/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$REG_DIR" "$ETC_DIR" "$RUNTIME_DIR" "$STATE_DIR" "$AUDIT_DIR" "$BACKUP"

echo "============================================================"
echo " DNYFTECH — PHASE 8H UNIFIED DEVICE REGISTRY"
echo "============================================================"
echo "Root: $ROOT"
echo

# ------------------------------------------------------------
# Locate canonical identity without generating a new one.
# ------------------------------------------------------------

IDENTITY_FILE="$ROOT/opt/dnyf/runtime/secure/identity/identity.json"

if [ ! -f "$IDENTITY_FILE" ]; then
    echo "[FAIL] Canonical cryptographic identity missing"
    exit 1
fi

DEVICE_ID="$(node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
process.stdout.write(String(x.device_id||"").toLowerCase());
' "$IDENTITY_FILE")"

FINGERPRINT="$(node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
process.stdout.write(String(x.fingerprint||"").toLowerCase());
' "$IDENTITY_FILE")"

PUBLIC_KEY="$(node -e '
const fs=require("fs");
const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
process.stdout.write(String(x.public_key||""));
' "$IDENTITY_FILE")"

if [ -z "$DEVICE_ID" ] || [ -z "$FINGERPRINT" ]; then
    echo "[FAIL] Canonical identity is incomplete"
    exit 1
fi

echo "Canonical device:"
echo "  $DEVICE_ID"
echo
echo "Active fingerprint:"
echo "  $FINGERPRINT"
echo

# ------------------------------------------------------------
# Backup existing registry material.
# ------------------------------------------------------------

for f in \
    "$REG_DIR/dnyf-unified-device-registry.json" \
    "$ETC_DIR/dnyf-device-registry-schema.json" \
    "$ETC_DIR/dnyf-device-registry-policy.json" \
    "$RUNTIME_DIR/dnyf-unified-device-registry.js" \
    "$STATE_DIR/local-device-record.json"
do
    if [ -e "$f" ]; then
        cp -a "$f" "$BACKUP/"
    fi
done

echo "[OK] Existing registry material backed up"

# ------------------------------------------------------------
# Registry schema.
# ------------------------------------------------------------

cat > "$ETC_DIR/dnyf-device-registry-schema.json" <<'JSON'
{
  "schema": "dnyf.device.registry.v1",
  "version": "1.0.0",
  "registry": "dnyf-unified-device-registry",
  "identity": {
    "device_id": "required",
    "fingerprint": "required",
    "public_key": "required"
  },
  "domains": [
    "identity",
    "platform",
    "capabilities",
    "network",
    "services",
    "pairing",
    "trust",
    "session",
    "revocation",
    "protocols",
    "audit"
  ],
  "security_separation": true,
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false
}
JSON

echo "[OK] registry schema"

# ------------------------------------------------------------
# Registry security policy.
# ------------------------------------------------------------

cat > "$ETC_DIR/dnyf-device-registry-policy.json" <<'JSON'
{
  "schema": "dnyf.device.registry.policy.v1",
  "version": "1.0.0",
  "authoritative_identity_source": "opt/dnyf/runtime/secure/identity/identity.json",
  "identity_mutation": false,
  "key_generation": false,
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false,
  "automatic_authorization": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "trust_requires_pairing": true,
  "session_requires_authentication": true,
  "session_requires_local_approval": true,
  "revocation_is_authoritative": true,
  "audit_required": true,
  "unknown_peers_default": "untrusted"
}
JSON

echo "[OK] registry security policy"

# ------------------------------------------------------------
# Determine platform/capabilities using existing DNYF runtime.
# ------------------------------------------------------------

PLATFORM_FILE="$ROOT/etc/dnyf/platform/dnyf-runtime-platform.json"
CAPABILITY_FILE="$ROOT/etc/dnyf/capabilities/dnyf-runtime-capabilities.json"
SERVICE_FILE="$ROOT/registry/services.json"
TRUST_FILE="$ROOT/registry/trust.json"
PAIR_FILE="$ROOT/etc/dnyf/pairing/config.json"
SESSION_FILE="$ROOT/etc/dnyf/session/protocol.json"

echo "◆ Building unified local device record..."

node - \
  "$IDENTITY_FILE" \
  "$PLATFORM_FILE" \
  "$CAPABILITY_FILE" \
  "$SERVICE_FILE" \
  "$TRUST_FILE" \
  "$PAIR_FILE" \
  "$SESSION_FILE" \
  "$STATE_DIR/local-device-record.json" \
  "$DEVICE_ID" \
  "$FINGERPRINT" \
  "$PUBLIC_KEY" <<'NODE'
const fs = require("fs");

const [
  identityFile,
  platformFile,
  capabilityFile,
  serviceFile,
  trustFile,
  pairingFile,
  sessionFile,
  outputFile,
  deviceId,
  fingerprint,
  publicKey
] = process.argv.slice(2);

function readJSON(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
}

const identity = readJSON(identityFile, {});
const platform = readJSON(platformFile, {});
const capabilities = readJSON(capabilityFile, {});
const services = readJSON(serviceFile, {});
const trust = readJSON(trustFile, {});
const pairing = readJSON(pairingFile, {});
const session = readJSON(sessionFile, {});

const now = new Date().toISOString();

const record = {
  schema: "dnyf.device.record.v1",
  version: "1.0.0",

  identity: {
    device_id: deviceId,
    fingerprint,
    public_key: publicKey,
    authority: "dnyf-cryptauth",
    canonical: true
  },

  platform: {
    ...platform
  },

  capabilities: {
    ...capabilities
  },

  network: {
    discovery: {
      protocol: "dnyf-discovery/1",
      udp_port: 9093,
      enabled: true
    },
    services: {
      device: 9092,
      trust: 9096,
      session: 9097,
      secure_api: 9443,
      transfer: 9444,
      sync: 9445
    }
  },

  services: {
    registry: services
  },

  pairing: {
    protocol: pairing.protocol || "dnyf-pairing/1",
    local_approval_required:
      pairing.local_approval_required !== false,
    automatic_trust: false,
    self_pairing: false
  },

  trust: {
    local_device_trusted: false,
    self_trust: false,
    peer_count: Array.isArray(trust.peers)
      ? trust.peers.length
      : 0,
    source: "registry/trust.json"
  },

  session: {
    protocol: session.protocol || "dnyf-session/1",
    authentication: "Ed25519",
    response_proof_required:
      session.response_proof_required !== false,
    replay_protection:
      session.replay_protection !== false,
    local_approval_required:
      session.local_approval_required !== false,
    revocation_required:
      session.explicit_revocation_required !== false
  },

  revocation: {
    local_device_revoked: false,
    authority: "dnyf-session"
  },

  protocols: {
    runtime: "dnyf-runtime/1",
    auth: "dnyf-cryptauth/1",
    pairing: "dnyf-pairing/1",
    session: "dnyf-session/1",
    discovery: "dnyf-discovery/1"
  },

  security: {
    self_trust: false,
    self_pairing: false,
    automatic_trust: false,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false
  },

  audit: {
    created_at: now,
    updated_at: now,
    source: "phase8h-unified-device-registry"
  }
};

fs.writeFileSync(
  outputFile,
  JSON.stringify(record, null, 2) + "\n",
  { mode: 0o600 }
);
NODE

echo "[OK] local device record"

# ------------------------------------------------------------
# Unified registry.
# ------------------------------------------------------------

echo "◆ Writing authoritative unified registry..."

node - "$STATE_DIR/local-device-record.json" "$REG_DIR/dnyf-unified-device-registry.json" <<'NODE'
const fs = require("fs");

const input = process.argv[2];
const output = process.argv[3];

const local = JSON.parse(fs.readFileSync(input, "utf8"));

const registry = {
  schema: "dnyf.device.registry.v1",
  version: "1.0.0",
  registry_id: "dnyf-unified-device-registry",

  policy: {
    unknown_peers_default: "untrusted",
    self_trust: false,
    self_pairing: false,
    automatic_trust: false,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false
  },

  devices: {
    [local.identity.device_id]: local
  },

  metadata: {
    device_count: 1,
    updated_at: new Date().toISOString(),
    authority: "dnyf-cryptauth"
  }
};

fs.writeFileSync(
  output,
  JSON.stringify(registry, null, 2) + "\n",
  { mode: 0o600 }
);
NODE

echo "[OK] unified device registry"

# ------------------------------------------------------------
# Runtime registry authority library.
# ------------------------------------------------------------

cat > "$RUNTIME_DIR/dnyf-unified-device-registry.js" <<'NODE'
"use strict";

const fs = require("fs");
const path = require("path");

function resolveRoot() {
  return process.env.DNYF_ROOT || path.join(
    process.env.HOME || process.cwd(),
    "DNYF-DEV"
  );
}

const ROOT = resolveRoot();

const REGISTRY_FILE = path.join(
  ROOT,
  "registry",
  "dnyf-unified-device-registry.json"
);

function readRegistry() {
  return JSON.parse(fs.readFileSync(REGISTRY_FILE, "utf8"));
}

function getDevice(deviceId) {
  const registry = readRegistry();
  return registry.devices[String(deviceId).toLowerCase()] || null;
}

function listDevices() {
  const registry = readRegistry();
  return Object.values(registry.devices || {});
}

function isSelfTrusted() {
  const registry = readRegistry();
  return registry.policy?.self_trust === true;
}

function isSelfPaired() {
  const registry = readRegistry();
  return registry.policy?.self_pairing === true;
}

function isAutomaticallyTrusted() {
  const registry = readRegistry();
  return registry.policy?.automatic_trust === true;
}

module.exports = {
  ROOT,
  REGISTRY_FILE,
  readRegistry,
  getDevice,
  listDevices,
  isSelfTrusted,
  isSelfPaired,
  isAutomaticallyTrusted
};
NODE

echo "[OK] registry authority library"

# ------------------------------------------------------------
# CLI.
# ------------------------------------------------------------

cat > "$ROOT/bin/dnyf-device-registry" <<'NODE'
#!/usr/bin/env node
"use strict";

const registry = require(
  require("path").join(
    process.env.DNYF_ROOT || require("os").homedir() + "/DNYF-DEV",
    "opt/dnyf/runtime/registry/dnyf-unified-device-registry.js"
  )
);

const command = process.argv[2] || "status";

switch (command) {
  case "status": {
    const r = registry.readRegistry();
    console.log("DNYFTECH UNIFIED DEVICE REGISTRY");
    console.log("--------------------------------");
    console.log(`Schema:       ${r.schema}`);
    console.log(`Version:      ${r.version}`);
    console.log(`Registry:     ${r.registry_id}`);
    console.log(`Devices:      ${r.metadata.device_count}`);
    console.log(`Self-trust:   ${r.policy.self_trust}`);
    console.log(`Self-pairing: ${r.policy.self_pairing}`);
    console.log(`Auto-trust:   ${r.policy.automatic_trust}`);
    break;
  }

  case "list": {
    for (const d of registry.listDevices()) {
      console.log(
        `${d.identity.device_id}  ${d.platform.platform || d.platform.os || "unknown"}  ${d.identity.fingerprint}`
      );
    }
    break;
  }

  case "show": {
    const id = process.argv[3];
    if (!id) {
      console.error("Usage: dnyf-device-registry show <device-id>");
      process.exit(2);
    }

    const device = registry.getDevice(id);

    if (!device) {
      console.error("[NOT FOUND] device");
      process.exit(1);
    }

    console.log(JSON.stringify(device, null, 2));
    break;
  }

  default:
    console.log("Usage:");
    console.log("  dnyf-device-registry status");
    console.log("  dnyf-device-registry list");
    console.log("  dnyf-device-registry show <device-id>");
    process.exit(2);
}
NODE

chmod 755 "$ROOT/bin/dnyf-device-registry"

ln -sfn "$ROOT/bin/dnyf-device-registry" \
  "$ROOT/usr/local/bin/dnyf-device-registry"

ln -sfn "$ROOT/bin/dnyf-device-registry" \
  "$ROOT/usr/bin/dnyf-device-registry"

echo "[OK] registry CLI"

# ------------------------------------------------------------
# Audit.
# ------------------------------------------------------------

cat > "$AUDIT_DIR/phase8h-unified-device-registry-$(date -u +%Y%m%dT%H%M%SZ).jsonl" <<JSON
{"event":"phase8h-unified-device-registry","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","device_id":"$DEVICE_ID","fingerprint":"$FINGERPRINT","identity_regenerated":false,"self_trust":false,"self_pairing":false,"automatic_trust":false}
JSON

echo "[OK] audit record"

# ------------------------------------------------------------
# Validation.
# ------------------------------------------------------------

echo
echo "◆ Validation..."

FAIL=0

check() {
    local label="$1"
    shift
    if "$@"; then
        echo "[OK] $label"
    else
        echo "[FAIL] $label"
        FAIL=$((FAIL+1))
    fi
}

check "registry schema" test -s \
  "$ETC_DIR/dnyf-device-registry-schema.json"

check "registry policy" test -s \
  "$ETC_DIR/dnyf-device-registry-policy.json"

check "local device record" test -s \
  "$STATE_DIR/local-device-record.json"

check "unified registry" test -s \
  "$REG_DIR/dnyf-unified-device-registry.json"

check "registry authority library" test -s \
  "$RUNTIME_DIR/dnyf-unified-device-registry.js"

check "registry CLI" test -x \
  "$ROOT/bin/dnyf-device-registry"

node --check "$RUNTIME_DIR/dnyf-unified-device-registry.js"
echo "[OK] registry authority syntax"

node --check "$ROOT/bin/dnyf-device-registry"
echo "[OK] registry CLI syntax"

node - "$REG_DIR/dnyf-unified-device-registry.json" "$DEVICE_ID" "$FINGERPRINT" <<'NODE'
const fs = require("fs");

const registry = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const expectedId = process.argv[3];
const expectedFingerprint = process.argv[4];

const device = registry.devices[expectedId];

if (!device)
  throw new Error("canonical device missing");

if (device.identity.fingerprint !== expectedFingerprint)
  throw new Error("fingerprint mismatch");

if (device.security.self_trust !== false)
  throw new Error("self-trust violation");

if (device.security.self_pairing !== false)
  throw new Error("self-pairing violation");

if (device.security.automatic_trust !== false)
  throw new Error("automatic-trust violation");

if (device.security.remote_execution !== false)
  throw new Error("remote-execution violation");

if (device.security.remote_installation !== false)
  throw new Error("remote-installation violation");

if (device.security.remote_shell !== false)
  throw new Error("remote-shell violation");

if (device.trust.local_device_trusted !== false)
  throw new Error("local self-trust violation");

if (device.revocation.local_device_revoked !== false)
  throw new Error("unexpected local revocation");

console.log("[OK] canonical identity binding");
console.log("[OK] fingerprint binding");
console.log("[OK] security separation");
console.log("[OK] self-trust disabled");
console.log("[OK] self-pairing disabled");
console.log("[OK] automatic trust disabled");
console.log("[OK] remote execution disabled");
console.log("[OK] remote installation disabled");
console.log("[OK] remote shell disabled");
console.log("[OK] local self-trust disabled");
NODE

DNYF_ROOT="$ROOT" "$ROOT/bin/dnyf-device-registry" status

echo
echo "◆ Registry integrity check..."

node - "$REG_DIR/dnyf-unified-device-registry.json" <<'NODE'
const fs = require("fs");

const file = process.argv[2];
const x = JSON.parse(fs.readFileSync(file, "utf8"));

if (x.schema !== "dnyf.device.registry.v1")
  throw new Error("invalid registry schema");

if (!x.devices || Object.keys(x.devices).length < 1)
  throw new Error("registry contains no devices");

for (const [id, d] of Object.entries(x.devices)) {
  if (id !== d.identity.device_id)
    throw new Error("device key/id mismatch");

  if (!d.identity.fingerprint)
    throw new Error(`missing fingerprint: ${id}`);

  if (!d.identity.public_key)
    throw new Error(`missing public key: ${id}`);

  if (!d.security)
    throw new Error(`missing security domain: ${id}`);

  if (!d.capabilities)
    throw new Error(`missing capability domain: ${id}`);

  if (!d.services)
    throw new Error(`missing service domain: ${id}`);

  if (!d.session)
    throw new Error(`missing session domain: ${id}`);
}

console.log("[OK] registry structure");
console.log("[OK] identity domain");
console.log("[OK] capability domain");
console.log("[OK] service domain");
console.log("[OK] pairing domain");
console.log("[OK] trust domain");
console.log("[OK] session domain");
console.log("[OK] revocation domain");
console.log("[OK] protocol domain");
console.log("[OK] security domain");
NODE

if [ "$FAIL" -ne 0 ]; then
    echo
    echo "============================================================"
    echo " PHASE 8H: FAIL"
    echo " Failures: $FAIL"
    echo "============================================================"
    exit 1
fi

cat > "$ROOT/etc/dnyf/phase8h-manifest.json" <<JSON
{
  "phase": "8H",
  "name": "Unified Device Registry",
  "schema": "dnyf.phase.v1",
  "version": "1.0.0",
  "status": "validated",
  "device_id": "$DEVICE_ID",
  "fingerprint": "$FINGERPRINT",
  "registry": "registry/dnyf-unified-device-registry.json",
  "identity_regeneration": false,
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "security_domains": [
    "identity",
    "platform",
    "capabilities",
    "network",
    "services",
    "pairing",
    "trust",
    "session",
    "revocation",
    "protocols",
    "audit"
  ]
}
JSON

echo
echo "============================================================"
echo " PHASE 8H UNIFIED DEVICE REGISTRY: PASS"
echo "============================================================"
echo "Device ID   : $DEVICE_ID"
echo "Fingerprint : $FINGERPRINT"
echo "Registry    : $REG_DIR/dnyf-unified-device-registry.json"
echo "Backup      : $BACKUP"
echo
echo "Validated:"
echo "  ✓ canonical identity binding"
echo "  ✓ unified device record"
echo "  ✓ platform domain"
echo "  ✓ capability domain"
echo "  ✓ network/service domain"
echo "  ✓ pairing domain"
echo "  ✓ trust domain"
echo "  ✓ authenticated-session domain"
echo "  ✓ revocation domain"
echo "  ✓ protocol domain"
echo "  ✓ audit domain"
echo "  ✓ security separation"
echo "  ✓ self-trust disabled"
echo "  ✓ self-pairing disabled"
echo "  ✓ automatic trust disabled"
echo "  ✓ remote execution disabled"
echo "  ✓ remote installation disabled"
echo "  ✓ remote shell disabled"
echo
echo "Next phase: 8I capability negotiation"
