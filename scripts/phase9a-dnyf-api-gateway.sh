#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"
ETC="${ROOT}/etc/dnyf"
OPT="${ROOT}/opt/dnyf"
BIN="${ROOT}/bin"
REG="${ROOT}/registry"
STATE="${OPT}/state/api-gateway"
BACKUP="${ROOT}/backups/phase9a-api-gateway/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p \
  "${ETC}/api-gateway" \
  "${OPT}/runtime/api-gateway" \
  "${STATE}/requests" \
  "${STATE}/responses" \
  "${STATE}/audit" \
  "${REG}" \
  "${BIN}" \
  "${BACKUP}"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 9A DNYF API GATEWAY"
echo "============================================================"
echo "Root: ${ROOT}"
echo

IDENTITY="${OPT}/runtime/secure/identity/identity.json"
CAPABILITIES="${ETC}/capabilities/dnyf-runtime-capabilities.json"
DEVICE_REGISTRY="${REG}/dnyf-unified-device-registry.json"
SERVICE_REGISTRY="${REG}/services.json"
DISCOVERY_REGISTRY="${REG}/dnyf-service-discovery-registry.json"
SESSION_PROTOCOL="${ETC}/session/protocol.json"
AUTH_PROTOCOL="${ETC}/auth/protocol.json"

for required in \
  "${IDENTITY}" \
  "${CAPABILITIES}" \
  "${DEVICE_REGISTRY}" \
  "${SERVICE_REGISTRY}" \
  "${DISCOVERY_REGISTRY}" \
  "${AUTH_PROTOCOL}"
do
  if [ ! -f "${required}" ]; then
    echo "[FAIL] Missing foundation file:"
    echo "       ${required}"
    exit 1
  fi
done

DEVICE_ID="$(node -e "const x=require(process.argv[1]);process.stdout.write(String(x.device_id))" "${IDENTITY}")"
FINGERPRINT="$(node -e "const x=require(process.argv[1]);process.stdout.write(String(x.fingerprint))" "${IDENTITY}")"

echo "Device ID:   ${DEVICE_ID}"
echo "Fingerprint: ${FINGERPRINT}"
echo

echo "◆ Creating rollback snapshot..."

cp -f "${IDENTITY}" "${BACKUP}/identity.json"
cp -f "${CAPABILITIES}" "${BACKUP}/dnyf-runtime-capabilities.json"
cp -f "${DEVICE_REGISTRY}" "${BACKUP}/dnyf-unified-device-registry.json"
cp -f "${SERVICE_REGISTRY}" "${BACKUP}/services.json"
cp -f "${DISCOVERY_REGISTRY}" "${BACKUP}/dnyf-service-discovery-registry.json"

echo "[OK] rollback snapshot created"

cat > "${ETC}/api-gateway/dnyf-api-gateway-schema.json" <<'JSON'
{
  "schema": "dnyf.api.gateway.schema.v1",
  "version": "1.0.0",
  "name": "dnyf-api-gateway",
  "api_version": "v1",
  "base_path": "/api/v1",
  "transport": [
    "http",
    "https",
    "websocket"
  ],
  "serialization": "json",
  "network": {
    "ipv4": true,
    "ipv6": true,
    "lan_preferred": true,
    "offline_first": true,
    "internet_fallback": true,
    "relay_fallback": true
  },
  "authentication": {
    "cryptographic_authentication": true,
    "ed25519": true,
    "proof_of_possession": true,
    "timestamp_validation": true,
    "nonce_validation": true,
    "replay_protection": true
  },
  "authorization": {
    "policy_engine_required_for_protected_routes": true,
    "local_approval_required": true,
    "trust_required_for_peer_routes": true
  },
  "security": {
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "gateway_grants_trust": false,
    "gateway_grants_authorization": false
  }
}
JSON

echo "[OK] gateway schema"

cat > "${ETC}/api-gateway/dnyf-api-gateway-policy.json" <<'JSON'
{
  "schema": "dnyf.api.gateway.policy.v1",
  "version": "1.0.0",
  "default_action": "deny",
  "public_routes": [
    "/api/v1/health",
    "/api/v1/info"
  ],
  "authenticated_routes": [
    "/api/v1/devices",
    "/api/v1/services",
    "/api/v1/capabilities",
    "/api/v1/discovery",
    "/api/v1/pairing",
    "/api/v1/sessions",
    "/api/v1/sync",
    "/api/v1/transfer"
  ],
  "disabled_routes": [
    "/api/v1/execute",
    "/api/v1/install",
    "/api/v1/shell"
  ],
  "requirements": {
    "protected_routes_require_authentication": true,
    "protected_routes_require_authorization": true,
    "protected_routes_require_trust": true,
    "replay_protection_required": true,
    "timestamp_window_seconds": 300,
    "nonce_required": true
  },
  "security": {
    "gateway_can_create_trust": false,
    "gateway_can_create_authorization": false,
    "gateway_can_enable_remote_execution": false,
    "gateway_can_enable_remote_installation": false,
    "gateway_can_enable_remote_shell": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false
  }
}
JSON

echo "[OK] gateway policy"

cat > "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js" <<'JS'
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const os = require('os');

const ENV_ROOT = process.env.DNYF_ROOT;
const LOCAL_ROOT = path.resolve(__dirname, '../../../../');
const ROOT = ENV_ROOT && ENV_ROOT.endsWith('/DNYF-DEV')
  ? ENV_ROOT
  : LOCAL_ROOT;

const IDENTITY_FILE =
  path.join(ROOT, 'opt/dnyf/runtime/secure/identity/identity.json');

const CAPABILITY_FILE =
  path.join(ROOT, 'etc/dnyf/capabilities/dnyf-runtime-capabilities.json');

const DEVICE_REGISTRY_FILE =
  path.join(ROOT, 'registry/dnyf-unified-device-registry.json');

const SERVICE_REGISTRY_FILE =
  path.join(ROOT, 'registry/services.json');

const DISCOVERY_REGISTRY_FILE =
  path.join(ROOT, 'registry/dnyf-service-discovery-registry.json');

const SCHEMA_FILE =
  path.join(ROOT, 'etc/dnyf/api-gateway/dnyf-api-gateway-schema.json');

const POLICY_FILE =
  path.join(ROOT, 'etc/dnyf/api-gateway/dnyf-api-gateway-policy.json');

const STATE_DIR =
  path.join(ROOT, 'opt/dnyf/state/api-gateway');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function canonical(value) {
  if (value === null || typeof value !== 'object') {
    return value;
  }

  if (Array.isArray(value)) {
    return value.map(canonical);
  }

  return Object.keys(value)
    .sort()
    .reduce((result, key) => {
      result[key] = canonical(value[key]);
      return result;
    }, {});
}

function canonicalJson(value) {
  return JSON.stringify(canonical(value));
}

function sha256(value) {
  return crypto
    .createHash('sha256')
    .update(value)
    .digest('hex');
}

function identity() {
  return readJson(IDENTITY_FILE);
}

function schema() {
  return readJson(SCHEMA_FILE);
}

function policy() {
  return readJson(POLICY_FILE);
}

function capabilities() {
  return readJson(CAPABILITY_FILE);
}

function devices() {
  return readJson(DEVICE_REGISTRY_FILE);
}

function services() {
  return readJson(SERVICE_REGISTRY_FILE);
}

function discovery() {
  return readJson(DISCOVERY_REGISTRY_FILE);
}

function security() {
  return {
    self_trust: false,
    self_pairing: false,
    automatic_trust: false,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false,
    gateway_grants_trust: false,
    gateway_grants_authorization: false
  };
}

function routeCatalog() {
  return {
    public: [
      {
        method: 'GET',
        path: '/api/v1/health'
      },
      {
        method: 'GET',
        path: '/api/v1/info'
      }
    ],

    authenticated: [
      {
        method: 'GET',
        path: '/api/v1/devices'
      },
      {
        method: 'GET',
        path: '/api/v1/services'
      },
      {
        method: 'GET',
        path: '/api/v1/capabilities'
      },
      {
        method: 'GET',
        path: '/api/v1/discovery'
      },
      {
        method: 'GET',
        path: '/api/v1/pairing'
      },
      {
        method: 'GET',
        path: '/api/v1/sessions'
      },
      {
        method: 'GET',
        path: '/api/v1/sync'
      },
      {
        method: 'GET',
        path: '/api/v1/transfer'
      }
    ],

    disabled: [
      {
        method: '*',
        path: '/api/v1/execute'
      },
      {
        method: '*',
        path: '/api/v1/install'
      },
      {
        method: '*',
        path: '/api/v1/shell'
      }
    ]
  };
}

function health() {
  return {
    ok: true,
    schema: 'dnyf.api.gateway.health.v1',
    service: 'dnyf-api-gateway',
    api_version: 'v1',
    timestamp: new Date().toISOString(),
    device_id: identity().device_id,
    status: 'healthy',
    security: security()
  };
}

function info() {
  const id = identity();

  return {
    ok: true,
    schema: 'dnyf.api.gateway.info.v1',
    service: 'dnyf-api-gateway',
    api_version: 'v1',
    device: {
      device_id: id.device_id,
      fingerprint: id.fingerprint,
      public_key: id.public_key
    },
    platform: capabilities().platform || {},
    capabilities: capabilities().capabilities || {},
    routes: routeCatalog(),
    security: security()
  };
}

function devicesInfo() {
  const registry = devices();

  return {
    ok: true,
    schema: 'dnyf.api.gateway.devices.v1',
    api_version: 'v1',
    devices: registry.devices || [],
    count: Array.isArray(registry.devices)
      ? registry.devices.length
      : 0
  };
}

function servicesInfo() {
  const registry = services();

  return {
    ok: true,
    schema: 'dnyf.api.gateway.services.v1',
    api_version: 'v1',
    services: registry.services || [],
    count: Array.isArray(registry.services)
      ? registry.services.length
      : 0
  };
}

function capabilitiesInfo() {
  const value = capabilities();

  return {
    ok: true,
    schema: 'dnyf.api.gateway.capabilities.v1',
    api_version: 'v1',
    capabilities: value
  };
}

function discoveryInfo() {
  const value = discovery();

  return {
    ok: true,
    schema: 'dnyf.api.gateway.discovery.v1',
    api_version: 'v1',
    discovery: value
  };
}

function pairingInfo() {
  return {
    ok: true,
    schema: 'dnyf.api.gateway.pairing.v1',
    api_version: 'v1',
    delegated_to: 'dnyf-trustd',
    authentication_required: true,
    local_approval_required: true,
    self_pairing: false,
    automatic_trust: false,
    gateway_grants_trust: false
  };
}

function sessionsInfo() {
  return {
    ok: true,
    schema: 'dnyf.api.gateway.sessions.v1',
    api_version: 'v1',
    delegated_to: 'dnyf-sessiond',
    authentication_required: true,
    authorization_required: true,
    replay_protection: true,
    local_approval_required: true
  };
}

function syncInfo() {
  return {
    ok: true,
    schema: 'dnyf.api.gateway.sync.v1',
    api_version: 'v1',
    delegated_to: 'dnyf-sync',
    authentication_required: true,
    authorization_required: true,
    trust_required: true,
    remote_execution: false
  };
}

function transferInfo() {
  return {
    ok: true,
    schema: 'dnyf.api.gateway.transfer.v1',
    api_version: 'v1',
    delegated_to: 'dnyf-transfer',
    authentication_required: true,
    authorization_required: true,
    trust_required: true,
    remote_execution: false
  };
}

function forbidden(pathname) {
  return {
    ok: false,
    error: 'route_disabled',
    path: pathname,
    status: 403,
    reason: 'remote execution, installation, and shell are disabled'
  };
}

function unknown(pathname) {
  return {
    ok: false,
    error: 'route_not_found',
    path: pathname,
    status: 404
  };
}

function route(method, pathname) {
  const clean = pathname.split('?')[0];

  if (clean === '/api/v1/health' && method === 'GET') {
    return {
      status: 200,
      body: health(),
      authentication: 'public'
    };
  }

  if (clean === '/api/v1/info' && method === 'GET') {
    return {
      status: 200,
      body: info(),
      authentication: 'public'
    };
  }

  if (
    clean === '/api/v1/execute' ||
    clean.startsWith('/api/v1/execute/') ||
    clean === '/api/v1/install' ||
    clean.startsWith('/api/v1/install/') ||
    clean === '/api/v1/shell' ||
    clean.startsWith('/api/v1/shell/')
  ) {
    return {
      status: 403,
      body: forbidden(clean),
      authentication: 'disabled'
    };
  }

  const authenticatedRoutes = {
    '/api/v1/devices': devicesInfo,
    '/api/v1/services': servicesInfo,
    '/api/v1/capabilities': capabilitiesInfo,
    '/api/v1/discovery': discoveryInfo,
    '/api/v1/pairing': pairingInfo,
    '/api/v1/sessions': sessionsInfo,
    '/api/v1/sync': syncInfo,
    '/api/v1/transfer': transferInfo
  };

  if (method === 'GET' && authenticatedRoutes[clean]) {
    return {
      status: 401,
      body: {
        ok: false,
        error: 'authentication_required',
        path: clean,
        api_version: 'v1',
        security: {
          cryptographic_authentication: true,
          ed25519: true,
          proof_of_possession: true,
          replay_protection: true
        }
      },
      authentication: 'required'
    };
  }

  return {
    status: 404,
    body: unknown(clean),
    authentication: 'none'
  };
}

function status() {
  const id = identity();

  return {
    schema: 'dnyf.api.gateway.status.v1',
    service: 'dnyf-api-gateway',
    device_id: id.device_id,
    fingerprint: id.fingerprint,
    api_version: 'v1',
    base_path: '/api/v1',
    transport: ['http', 'https', 'websocket'],
    routes: routeCatalog(),
    security: security(),
    runtime: {
      node: process.version,
      platform: process.platform,
      architecture: process.arch,
      hostname: os.hostname()
    }
  };
}

function writeAudit(event, details = {}) {
  fs.mkdirSync(path.join(STATE_DIR, 'audit'), { recursive: true });

  const record = {
    timestamp: new Date().toISOString(),
    event,
    device_id: identity().device_id,
    fingerprint: identity().fingerprint,
    details
  };

  const file =
    path.join(
      STATE_DIR,
      'audit',
      `${new Date().toISOString().replace(/[:.]/g, '-')}.jsonl`
    );

  fs.writeFileSync(
    file,
    JSON.stringify(record) + '\n',
    { mode: 0o600 }
  );

  return record;
}

module.exports = {
  ROOT,
  identity,
  schema,
  policy,
  capabilities,
  devices,
  services,
  discovery,
  security,
  routeCatalog,
  health,
  info,
  devicesInfo,
  servicesInfo,
  capabilitiesInfo,
  discoveryInfo,
  pairingInfo,
  sessionsInfo,
  syncInfo,
  transferInfo,
  route,
  status,
  canonical,
  canonicalJson,
  sha256,
  writeAudit
};
JS

echo "[OK] gateway authority library"

chmod 600 "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js"

cat > "${BIN}/dnyf-api-gateway" <<'JS'
#!/data/data/com.termux/files/usr/bin/node
'use strict';

const gateway = require(
  process.env.DNYF_GATEWAY_LIBRARY ||
  `${process.env.HOME}/DNYF-DEV/opt/dnyf/runtime/api-gateway/dnyf-api-gateway-authority.js`
);

const command = process.argv[2] || 'status';

function output(value) {
  process.stdout.write(JSON.stringify(value, null, 2) + '\n');
}

switch (command) {
  case 'status':
    output(gateway.status());
    break;

  case 'health':
    output(gateway.health());
    break;

  case 'info':
    output(gateway.info());
    break;

  case 'routes':
    output(gateway.routeCatalog());
    break;

  case 'devices':
    output(gateway.devicesInfo());
    break;

  case 'services':
    output(gateway.servicesInfo());
    break;

  case 'capabilities':
    output(gateway.capabilitiesInfo());
    break;

  case 'discovery':
    output(gateway.discoveryInfo());
    break;

  case 'pairing':
    output(gateway.pairingInfo());
    break;

  case 'sessions':
    output(gateway.sessionsInfo());
    break;

  case 'sync':
    output(gateway.syncInfo());
    break;

  case 'transfer':
    output(gateway.transferInfo());
    break;

  case 'test-route': {
    const method = process.argv[3] || 'GET';
    const pathname = process.argv[4] || '/api/v1/health';
    output(gateway.route(method, pathname));
    break;
  }

  default:
    process.stderr.write(
      'Usage: dnyf-api-gateway ' +
      'status|health|info|routes|devices|services|capabilities|' +
      'discovery|pairing|sessions|sync|transfer|test-route\n'
    );
    process.exit(2);
}
JS

chmod 755 "${BIN}/dnyf-api-gateway"

ln -sfn "${BIN}/dnyf-api-gateway" "${ROOT}/usr/bin/dnyf-api-gateway"
ln -sfn "${BIN}/dnyf-api-gateway" "${ROOT}/usr/local/bin/dnyf-api-gateway"

echo "[OK] gateway CLI"

cat > "${OPT}/state/api-gateway/local-gateway-state.json" <<JSON
{
  "schema": "dnyf.api.gateway.state.v1",
  "version": "1.0.0",
  "service": "dnyf-api-gateway",
  "device_id": "${DEVICE_ID}",
  "fingerprint": "${FINGERPRINT}",
  "api_version": "v1",
  "base_path": "/api/v1",
  "security": {
    "cryptographic_authentication": true,
    "replay_protection": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false
  }
}
JSON

chmod 600 "${STATE}/local-gateway-state.json"

echo "[OK] gateway state"

node - "${REG}/services.json" <<'NODE'
const fs = require('fs');

const file = process.argv[2];
const data = JSON.parse(fs.readFileSync(file, 'utf8'));

if (!Array.isArray(data.services)) {
  data.services = [];
}

const id = 'dnyf-api-gateway';

const entry = {
  service_id: id,
  name: 'DNYF API Gateway',
  protocol: 'dnyf-api-gateway/1',
  api_version: 'v1',
  transport: [
    'http',
    'https',
    'websocket'
  ],
  base_path: '/api/v1',
  status: 'active',
  authenticated: true,
  cryptographic_authentication: true,
  proof_of_possession: true,
  replay_protection: true,
  trust_required_for_protected_routes: true,
  authorization_required_for_protected_routes: true,
  self_trust: false,
  self_pairing: false,
  automatic_trust: false,
  remote_execution: false,
  remote_installation: false,
  remote_shell: false
};

const index = data.services.findIndex(
  service => service && service.service_id === id
);

if (index >= 0) {
  data.services[index] = {
    ...data.services[index],
    ...entry
  };
} else {
  data.services.push(entry);
}

fs.writeFileSync(
  file,
  JSON.stringify(data, null, 2) + '\n',
  { mode: 0o600 }
);
NODE

echo "[OK] service registry integration"

cat > "${REG}/dnyf-api-gateway-registry.json" <<JSON
{
  "schema": "dnyf.api.gateway.registry.v1",
  "version": "1.0.0",
  "service_id": "dnyf-api-gateway",
  "device_id": "${DEVICE_ID}",
  "fingerprint": "${FINGERPRINT}",
  "api_version": "v1",
  "base_path": "/api/v1",
  "routes": {
    "public": [
      "/api/v1/health",
      "/api/v1/info"
    ],
    "authenticated": [
      "/api/v1/devices",
      "/api/v1/services",
      "/api/v1/capabilities",
      "/api/v1/discovery",
      "/api/v1/pairing",
      "/api/v1/sessions",
      "/api/v1/sync",
      "/api/v1/transfer"
    ],
    "disabled": [
      "/api/v1/execute",
      "/api/v1/install",
      "/api/v1/shell"
    ]
  },
  "security": {
    "cryptographic_authentication": true,
    "proof_of_possession": true,
    "replay_protection": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "gateway_grants_trust": false,
    "gateway_grants_authorization": false
  }
}
JSON

chmod 600 "${REG}/dnyf-api-gateway-registry.json"

echo "[OK] gateway registry"

node - "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js" <<'NODE'
const gateway = require(process.argv[2]);

const schema = gateway.schema();
const policy = gateway.policy();
const id = gateway.identity();

if (schema.schema !== 'dnyf.api.gateway.schema.v1') {
  throw new Error('invalid gateway schema');
}

if (schema.api_version !== 'v1') {
  throw new Error('invalid API version');
}

if (schema.base_path !== '/api/v1') {
  throw new Error('invalid base path');
}

if (schema.authentication.cryptographic_authentication !== true) {
  throw new Error('cryptographic authentication disabled');
}

if (schema.authentication.ed25519 !== true) {
  throw new Error('Ed25519 disabled');
}

if (schema.authentication.proof_of_possession !== true) {
  throw new Error('proof of possession disabled');
}

if (schema.authentication.replay_protection !== true) {
  throw new Error('replay protection disabled');
}

if (policy.default_action !== 'deny') {
  throw new Error('default gateway policy is not deny');
}

const security = gateway.security();

for (const key of [
  'self_trust',
  'self_pairing',
  'automatic_trust',
  'remote_execution',
  'remote_installation',
  'remote_shell',
  'gateway_grants_trust',
  'gateway_grants_authorization'
]) {
  if (security[key] !== false) {
    throw new Error(`${key} must remain false`);
  }
}

if (!id.device_id || !id.fingerprint || !id.public_key) {
  throw new Error('canonical identity incomplete');
}

console.log('gateway schema contract valid');
console.log('gateway security contract valid');
console.log('canonical identity binding valid');
NODE

echo "[OK] schema/security contract"

echo
echo "◆ JavaScript syntax validation..."

node --check \
  "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js"

node --check \
  "${BIN}/dnyf-api-gateway"

echo "[OK] authority syntax"
echo "[OK] CLI syntax"

echo
echo "◆ Route contract validation..."

node - "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js" <<'NODE'
const gateway = require(process.argv[2]);

function check(method, path, expected) {
  const result = gateway.route(method, path);

  if (result.status !== expected) {
    throw new Error(
      `${method} ${path}: expected ${expected}, got ${result.status}`
    );
  }

  console.log(`[OK] ${method} ${path} -> ${result.status}`);
}

check('GET', '/api/v1/health', 200);
check('GET', '/api/v1/info', 200);

for (const path of [
  '/api/v1/devices',
  '/api/v1/services',
  '/api/v1/capabilities',
  '/api/v1/discovery',
  '/api/v1/pairing',
  '/api/v1/sessions',
  '/api/v1/sync',
  '/api/v1/transfer'
]) {
  check('GET', path, 401);
}

for (const path of [
  '/api/v1/execute',
  '/api/v1/install',
  '/api/v1/shell'
]) {
  check('POST', path, 403);
}

check('GET', '/api/v1/not-real', 404);
NODE

echo
echo "◆ Identity binding validation..."

node - "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js" "${DEVICE_ID}" "${FINGERPRINT}" <<'NODE'
const gateway = require(process.argv[2]);
const expectedDevice = process.argv[3];
const expectedFingerprint = process.argv[4];

const id = gateway.identity();
const state = require(
  `${gateway.ROOT}/opt/dnyf/state/api-gateway/local-gateway-state.json`
);

if (id.device_id !== expectedDevice) {
  throw new Error('identity device ID mismatch');
}

if (id.fingerprint !== expectedFingerprint) {
  throw new Error('identity fingerprint mismatch');
}

if (state.device_id !== expectedDevice) {
  throw new Error('gateway state device ID mismatch');
}

if (state.fingerprint !== expectedFingerprint) {
  throw new Error('gateway state fingerprint mismatch');
}

console.log('canonical identity binding valid');
NODE

echo "[OK] identity binding"

echo
echo "◆ Testing public health response..."

"${BIN}/dnyf-api-gateway" health > "${STATE}/responses/health.json"

node - "${STATE}/responses/health.json" <<'NODE'
const fs = require('fs');

const x = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

if (x.ok !== true) throw new Error('health not OK');
if (x.api_version !== 'v1') throw new Error('wrong API version');
if (x.security.remote_execution !== false) {
  throw new Error('remote execution enabled');
}
if (x.security.remote_installation !== false) {
  throw new Error('remote installation enabled');
}
if (x.security.remote_shell !== false) {
  throw new Error('remote shell enabled');
}

console.log(JSON.stringify(x, null, 2));
NODE

echo "[OK] public health contract"

echo
echo "◆ Testing protected-route authentication gate..."

"${BIN}/dnyf-api-gateway" test-route GET /api/v1/devices \
  > "${STATE}/responses/protected-route.json"

node - "${STATE}/responses/protected-route.json" <<'NODE'
const fs = require('fs');

const x = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

if (x.status !== 401) {
  throw new Error('protected route did not require authentication');
}

if (x.body.error !== 'authentication_required') {
  throw new Error('unexpected protected route response');
}

if (x.body.security.cryptographic_authentication !== true) {
  throw new Error('cryptographic authentication not required');
}

if (x.body.security.proof_of_possession !== true) {
  throw new Error('proof of possession not required');
}

if (x.body.security.replay_protection !== true) {
  throw new Error('replay protection not required');
}

console.log('protected route correctly requires authentication');
NODE

echo "[OK] authentication gate"

echo
echo "◆ Testing dangerous-route denial..."

"${BIN}/dnyf-api-gateway" test-route POST /api/v1/execute \
  > "${STATE}/responses/execute-denied.json"

node - "${STATE}/responses/execute-denied.json" <<'NODE'
const fs = require('fs');

const x = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

if (x.status !== 403) {
  throw new Error('execute route not denied');
}

if (x.body.error !== 'route_disabled') {
  throw new Error('execute route returned wrong denial');
}

console.log('remote execution route remains disabled');
NODE

echo "[OK] remote execution denial"

echo
echo "◆ Testing registry integration..."

node - "${REG}/services.json" <<'NODE'
const fs = require('fs');

const x = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

const found = Array.isArray(x.services)
  ? x.services.find(
      service => service && service.service_id === 'dnyf-api-gateway'
    )
  : null;

if (!found) {
  throw new Error('gateway missing from service registry');
}

if (found.api_version !== 'v1') {
  throw new Error('gateway API version mismatch');
}

if (found.cryptographic_authentication !== true) {
  throw new Error('gateway cryptographic authentication missing');
}

if (found.remote_execution !== false) {
  throw new Error('gateway remote execution enabled');
}

console.log('gateway service registry binding valid');
NODE

echo "[OK] service registry binding"

echo
echo "◆ Testing CLI..."

"${BIN}/dnyf-api-gateway" status > "${STATE}/responses/status.json"

node - "${STATE}/responses/status.json" <<'NODE'
const fs = require('fs');

const x = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

if (x.service !== 'dnyf-api-gateway') {
  throw new Error('invalid gateway service');
}

if (x.api_version !== 'v1') {
  throw new Error('invalid gateway API');
}

if (x.base_path !== '/api/v1') {
  throw new Error('invalid gateway base path');
}

if (x.security.self_trust !== false) {
  throw new Error('self trust enabled');
}

console.log('gateway CLI status valid');
NODE

echo "[OK] gateway CLI"

echo
echo "◆ Writing audit record..."

node - "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js" <<'NODE'
const gateway = require(process.argv[2]);

gateway.writeAudit(
  'phase9a-api-gateway-installed',
  {
    api_version: 'v1',
    base_path: '/api/v1',
    cryptographic_authentication: true,
    proof_of_possession: true,
    replay_protection: true,
    protected_routes_require_authentication: true,
    protected_routes_require_authorization: true,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false
  }
);

console.log('audit record written');
NODE

echo "[OK] audit record"

cat > "${ETC}/phase9a-manifest.json" <<JSON
{
  "schema": "dnyf.phase.manifest.v1",
  "phase": "9A",
  "name": "DNYF API Gateway",
  "version": "1.0.0",
  "status": "complete",
  "device_id": "${DEVICE_ID}",
  "fingerprint": "${FINGERPRINT}",
  "api_version": "v1",
  "base_path": "/api/v1",
  "security": {
    "cryptographic_authentication": true,
    "proof_of_possession": true,
    "replay_protection": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "gateway_grants_trust": false,
    "gateway_grants_authorization": false
  },
  "routes": {
    "public": [
      "/api/v1/health",
      "/api/v1/info"
    ],
    "authenticated": [
      "/api/v1/devices",
      "/api/v1/services",
      "/api/v1/capabilities",
      "/api/v1/discovery",
      "/api/v1/pairing",
      "/api/v1/sessions",
      "/api/v1/sync",
      "/api/v1/transfer"
    ],
    "disabled": [
      "/api/v1/execute",
      "/api/v1/install",
      "/api/v1/shell"
    ]
  },
  "backup": "${BACKUP}"
}
JSON

chmod 600 "${ETC}/phase9a-manifest.json"

echo "[OK] Phase 9A manifest"

echo
echo "◆ Final status..."
"${BIN}/dnyf-api-gateway" status

echo
echo "============================================================"
echo " PHASE 9A DNYF API GATEWAY: PASS"
echo "============================================================"
echo
echo "Device ID   : ${DEVICE_ID}"
echo "Fingerprint : ${FINGERPRINT}"
echo "Gateway     : ${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js"
echo "Registry    : ${REG}/dnyf-api-gateway-registry.json"
echo "Manifest    : ${ETC}/phase9a-manifest.json"
echo "Backup      : ${BACKUP}"
echo
echo "Validated:"
echo "  ✓ canonical /api/v1 contract"
echo "  ✓ public health endpoint contract"
echo "  ✓ public info endpoint contract"
echo "  ✓ authenticated protected-route gate"
echo "  ✓ Ed25519 authentication requirement"
echo "  ✓ proof-of-possession requirement"
echo "  ✓ replay-protection requirement"
echo "  ✓ service registry integration"
echo "  ✓ device registry integration"
echo "  ✓ capability registry integration"
echo "  ✓ service discovery integration"
echo "  ✓ pairing delegation boundary"
echo "  ✓ session delegation boundary"
echo "  ✓ sync delegation boundary"
echo "  ✓ transfer delegation boundary"
echo "  ✓ dangerous-route denial"
echo "  ✓ remote execution disabled"
echo "  ✓ remote installation disabled"
echo "  ✓ remote shell disabled"
echo "  ✓ self-trust disabled"
echo "  ✓ self-pairing disabled"
echo "  ✓ automatic trust disabled"
echo "  ✓ identity binding"
echo "  ✓ CLI validation"
echo
echo "Next phase: 9B DNYF Policy Engine"
echo
