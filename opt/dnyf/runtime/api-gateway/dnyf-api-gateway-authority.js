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
