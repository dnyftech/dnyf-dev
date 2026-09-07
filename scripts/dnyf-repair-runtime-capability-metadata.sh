#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${HOME}/DNYF-DEV"
CAP_DIR="${ROOT}/etc/dnyf/capabilities"
CAP_FILE="${CAP_DIR}/dnyf-runtime-capabilities.json"
PLATFORM_FILE="${ROOT}/etc/dnyf/platform/dnyf-runtime-platform.json"
IDENTITY_FILE="${ROOT}/opt/dnyf/runtime/secure/identity/identity.json"
BACKUP_DIR="${ROOT}/backups/runtime-capability-repair/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$CAP_DIR" "$BACKUP_DIR"

echo
echo "============================================================"
echo " DNYFTECH — RUNTIME CAPABILITY METADATA REPAIR"
echo "============================================================"
echo "Root: $ROOT"
echo

if [ -f "$CAP_FILE" ]; then
  cp -a "$CAP_FILE" "$BACKUP_DIR/dnyf-runtime-capabilities.json.before"
  echo "[OK] Existing capability metadata backed up"
fi

if [ ! -f "$IDENTITY_FILE" ]; then
  echo "[FAIL] Canonical identity missing"
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

if [ -z "$DEVICE_ID" ] || [ -z "$FINGERPRINT" ]; then
  echo "[FAIL] Canonical identity incomplete"
  exit 1
fi

echo "[OK] Canonical identity loaded"

node - "$CAP_FILE" "$PLATFORM_FILE" "$DEVICE_ID" "$FINGERPRINT" <<'NODE'
const fs = require('fs');
const os = require('os');
const cp = require('child_process');

const capFile = process.argv[2];
const platformFile = process.argv[3];
const deviceId = process.argv[4];
const fingerprint = process.argv[5];

let platform = {};

if (fs.existsSync(platformFile)) {
  try {
    platform = JSON.parse(fs.readFileSync(platformFile, 'utf8'));
  } catch (_) {}
}

function commandExists(command) {
  try {
    cp.execFileSync(
      'sh',
      ['-c', `command -v ${command} >/dev/null 2>&1`],
      {stdio:'ignore'}
    );
    return true;
  } catch (_) {
    return false;
  }
}

function normalizeArch(value) {
  const x = String(value || '').toLowerCase();

  if (
    x === 'aarch64' ||
    x === 'arm64' ||
    x === 'armv8' ||
    x === 'armv8l'
  ) return 'arm64';

  if (
    x === 'arm' ||
    x === 'armv7l' ||
    x === 'armv7'
  ) return 'arm32';

  if (
    x === 'x86_64' ||
    x === 'amd64'
  ) return 'x86_64';

  if (
    x === 'x86' ||
    x === 'i386' ||
    x === 'i686'
  ) return 'x86';

  if (x === 'riscv64') return 'riscv64';

  return x || 'unknown';
}

function detectPlatform() {
  const p = String(process.platform || '').toLowerCase();

  if (p === 'android') return 'android';
  if (p === 'win32') return 'windows';
  if (p === 'darwin') return 'macos';
  if (p === 'linux') return 'linux';

  return p || 'unknown';
}

const architecture = normalizeArch(
  platform.architecture ||
  platform.arch ||
  process.arch
);

const detectedPlatform = detectPlatform();

const logicalCores = Math.max(
  1,
  Array.isArray(os.cpus()) ? os.cpus().length : 1
);

const memoryBytes = Number(os.totalmem()) || 0;

const tools = [
  'node',
  'curl',
  'openssl',
  'tar',
  'unzip',
  'git',
  'wget',
  'python3',
  'zip',
  'proot',
  'ollama',
  'java',
  'javac'
].filter(commandExists);

const capability = {
  schema: 'dnyf.runtime.capabilities.v1',
  version: '1.0.0',

  device: {
    device_id: deviceId,
    fingerprint
  },

  platform: {
    os: detectedPlatform,
    architecture,
    node_platform: process.platform,
    node_architecture: process.arch,
    runtime: 'node',
    node_version: process.version
  },

  cpu: {
    logical_cores: logicalCores,
    normalized_logical_cores: logicalCores
  },

  memory: {
    memory_bytes: memoryBytes
  },

  resources: {
    logical_cores: logicalCores,
    memory_bytes: memoryBytes
  },

  network: {
    ipv4: true,
    ipv6: true,
    dns: true,
    http: true,
    https: true,
    websocket: true,
    offline_first: true,
    lan_preferred: true,
    internet_fallback: true,
    relay_fallback: true
  },

  transport: {
    local_process: true,
    http: true,
    https: true,
    websocket: true
  },

  security: {
    ed25519: true,
    sha256: true,
    cryptographic_authentication: true,
    proof_of_possession: true,
    self_trust: false,
    self_pairing: false,
    automatic_trust: false
  },

  execution: {
    local_process: true,
    artifact_inspection: true,
    metadata_analysis: true,

    remote_execution: false,
    remote_installation: false,
    remote_shell: false
  },

  tools: {
    available: tools
  },

  tool_availability: Object.fromEntries(
    [
      'node',
      'curl',
      'openssl',
      'tar',
      'unzip',
      'git',
      'wget',
      'python3',
      'zip',
      'proot',
      'ollama',
      'java',
      'javac'
    ].map(x => [x, commandExists(x)])
  ),

  protocol: {
    runtime_protocol: 'dnyf-runtime/1',
    capability_protocol: 'dnyf-capability/1',
    api_versions: ['v1'],
    protocol_versions: ['1.0.0']
  },

  generated_at: new Date().toISOString()
};

fs.writeFileSync(
  capFile,
  JSON.stringify(capability, null, 2) + '\n',
  {mode:0o600}
);

console.log('[OK] Capability metadata reconstructed');
console.log(`Platform       : ${detectedPlatform}`);
console.log(`Architecture   : ${architecture}`);
console.log(`Logical cores  : ${logicalCores}`);
console.log(`Memory bytes   : ${memoryBytes}`);
console.log(`Tools detected : ${tools.length}`);
NODE

chmod 600 "$CAP_FILE"

echo "[OK] Capability metadata permissions set"

echo "◆ Validating capability metadata..."

node - "$CAP_FILE" "$DEVICE_ID" "$FINGERPRINT" <<'NODE'
const fs=require('fs');

const file=process.argv[2];
const deviceId=process.argv[3];
const fingerprint=process.argv[4];

const x=JSON.parse(fs.readFileSync(file,'utf8'));

if(x.schema!=='dnyf.runtime.capabilities.v1')
  throw new Error('invalid capability schema');

if(x.version!=='1.0.0')
  throw new Error('invalid capability version');

if(x.device.device_id!==deviceId)
  throw new Error('device ID binding failure');

if(x.device.fingerprint!==fingerprint)
  throw new Error('fingerprint binding failure');

if(!x.platform.architecture)
  throw new Error('architecture missing');

if(!x.platform.os)
  throw new Error('platform missing');

if(!(Number(x.cpu.normalized_logical_cores)>=1))
  throw new Error('logical core normalization failure');

if(x.security.self_trust!==false)
  throw new Error('self trust must remain disabled');

if(x.security.self_pairing!==false)
  throw new Error('self pairing must remain disabled');

if(x.security.automatic_trust!==false)
  throw new Error('automatic trust must remain disabled');

if(x.execution.remote_execution!==false)
  throw new Error('remote execution must remain disabled');

if(x.execution.remote_installation!==false)
  throw new Error('remote installation must remain disabled');

if(x.execution.remote_shell!==false)
  throw new Error('remote shell must remain disabled');

console.log('[OK] Capability metadata contract valid');
NODE

echo
echo "============================================================"
echo " RUNTIME CAPABILITY METADATA REPAIR: PASS"
echo "============================================================"
echo "Capability file:"
echo "  $CAP_FILE"
echo
echo "Backup:"
echo "  $BACKUP_DIR"
echo
echo "◆ Rerunning Phase 8I..."
echo

bash "$ROOT/scripts/phase8i-capability-negotiation.sh"
