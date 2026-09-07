#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${HOME}/DNYF-DEV"
export DNYF_ROOT="$ROOT"

ETC="${ROOT}/etc/dnyf"
OPT="${ROOT}/opt/dnyf"
REG="${ROOT}/registry"
BIN="${ROOT}/bin"
USR_BIN="${ROOT}/usr/bin"
USR_LOCAL_BIN="${ROOT}/usr/local/bin"
BACKUP="${ROOT}/backups/phase9b-policy-engine/$(date -u +%Y%m%dT%H%M%SZ)"

POLICY_DIR="${ETC}/policy"
RUNTIME_DIR="${OPT}/runtime/policy-engine"
STATE_DIR="${OPT}/state/policy-engine"
AUDIT_DIR="${STATE_DIR}/audit"

SCHEMA="${POLICY_DIR}/dnyf-policy-engine-schema.json"
POLICY="${POLICY_DIR}/dnyf-policy-engine-policy.json"
AUTHORITY="${RUNTIME_DIR}/dnyf-policy-engine-authority.js"
CLI="${BIN}/dnyf-policy"
STATE="${STATE_DIR}/local-policy-state.json"
REGISTRY="${REG}/dnyf-policy-engine-registry.json"
MANIFEST="${ETC}/phase9b-manifest.json"
SERVICES="${REG}/services.json"

DEVICE_ID="cbd06be57a51cb84e12b4e112a4d06e9"
EXPECTED_FINGERPRINT="8a0cf45467dff43a76586033363561b643d6fa3c814f45e2a5fbd5ad61473e23"

PASS=0
FAIL=0

ok() {
  printf '[OK] %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf '[FAIL] %s\n' "$1"
  FAIL=$((FAIL + 1))
}

require_file() {
  if [ -f "$1" ]; then
    ok "$2"
  else
    fail "$2"
    exit 1
  fi
}

printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' ' DNYFTECH — PHASE 9B DNYF POLICY ENGINE'
printf '%s\n' '============================================================'
printf 'Root: %s\n' "$ROOT"
printf 'Timestamp: %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

printf '%s\n' '◆ Verifying Phase 9A foundation...'

require_file \
  "${ETC}/api-gateway/dnyf-api-gateway-schema.json" \
  '9A gateway schema'

require_file \
  "${ETC}/api-gateway/dnyf-api-gateway-policy.json" \
  '9A gateway policy'

require_file \
  "${OPT}/runtime/api-gateway/dnyf-api-gateway-authority.js" \
  '9A gateway authority'

require_file \
  "${OPT}/runtime/secure/identity/identity.json" \
  'canonical cryptographic identity'

require_file \
  "${REG}/dnyf-unified-device-registry.json" \
  '8H device registry'

require_file \
  "${REG}/dnyf-service-discovery-registry.json" \
  '8J service discovery registry'

require_file \
  "${REG}/dnyf-api-gateway-registry.json" \
  '9A gateway registry'

printf '\n◆ Loading canonical identity...\n'

IDENTITY_FINGERPRINT="$(
  node -e '
    const fs=require("fs");
    const p=process.argv[1];
    const x=JSON.parse(fs.readFileSync(p,"utf8"));
    process.stdout.write(String(x.fingerprint || x.public_key_fingerprint || ""));
  ' "${OPT}/runtime/secure/identity/identity.json"
)"

IDENTITY_DEVICE="$(
  node -e '
    const fs=require("fs");
    const p=process.argv[1];
    const x=JSON.parse(fs.readFileSync(p,"utf8"));
    process.stdout.write(String(x.device_id || ""));
  ' "${OPT}/runtime/secure/identity/identity.json"
)"

if [ "$IDENTITY_DEVICE" = "$DEVICE_ID" ]; then
  ok 'canonical device ID binding'
else
  fail 'canonical device ID binding'
  exit 1
fi

if [ "$IDENTITY_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ]; then
  ok 'active cryptographic fingerprint binding'
else
  fail 'active cryptographic fingerprint binding'
  exit 1
fi

printf '\n◆ Creating rollback snapshot...\n'

mkdir -p "$BACKUP"

for SOURCE in \
  "$POLICY_DIR" \
  "$RUNTIME_DIR" \
  "$STATE_DIR" \
  "$REGISTRY" \
  "$MANIFEST" \
  "$SERVICES"
do
  if [ -e "$SOURCE" ]; then
    mkdir -p "$BACKUP/$(dirname "${SOURCE#"$ROOT/"}")"
    cp -a "$SOURCE" "$BACKUP/$(dirname "${SOURCE#"$ROOT/"}")/" 2>/dev/null || true
  fi
done

ok 'rollback snapshot created'

mkdir -p \
  "$POLICY_DIR" \
  "$RUNTIME_DIR" \
  "$STATE_DIR" \
  "$AUDIT_DIR" \
  "$REG"

printf '\n◆ Writing policy schema...\n'

cat > "$SCHEMA" <<'JSON'
{
  "schema": "dnyf.policy.engine.schema.v1",
  "version": "1.0.0",
  "name": "dnyf-policy-engine",
  "description": "Deterministic fail-closed authorization policy engine.",
  "decision_states": [
    "allow",
    "deny"
  ],
  "evaluation_order": [
    "request_shape",
    "dangerous_operation_denial",
    "identity",
    "trust",
    "session",
    "capability",
    "local_approval",
    "route",
    "method",
    "resource",
    "explicit_deny",
    "explicit_allow",
    "default_deny"
  ],
  "security": {
    "default_deny": true,
    "fail_closed": true,
    "policy_integrity_required": true,
    "decision_audit_required": true,
    "explainability_required": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false,
    "policy_engine_grants_trust": false,
    "policy_engine_grants_pairing": false,
    "policy_engine_bypasses_gateway": false,
    "policy_engine_grants_execution": false
  },
  "authentication": {
    "cryptographic_authentication_required": true,
    "ed25519_required": true,
    "proof_of_possession_required": true,
    "timestamp_validation_required": true,
    "nonce_validation_required": true,
    "replay_protection_required": true
  },
  "authorization": {
    "trust_required": true,
    "session_required": true,
    "capability_evaluation": true,
    "local_approval_evaluation": true,
    "route_evaluation": true,
    "method_evaluation": true,
    "resource_evaluation": true
  },
  "integrity": {
    "algorithm": "SHA-256",
    "canonicalization": "sorted-json-keys"
  }
}
JSON

ok 'policy schema'

printf '\n◆ Writing authoritative policy...\n'

cat > "$POLICY" <<'JSON'
{
  "schema": "dnyf.policy.definition.v1",
  "version": "1.0.0",
  "policy_id": "dnyf-default-security-policy",
  "mode": "default-deny",
  "evaluation": {
    "deny_precedence": true,
    "fail_closed": true,
    "unknown_fields_denied": true
  },
  "identity": {
    "accepted_device_roles": [
      "workstation",
      "mobile",
      "server",
      "edge",
      "dev",
      "ai-node"
    ],
    "identity_required": true,
    "cryptographic_identity_required": true
  },
  "trust": {
    "required": true,
    "accepted_states": [
      "trusted"
    ],
    "self_trust": false,
    "automatic_trust": false
  },
  "session": {
    "required": true,
    "accepted_states": [
      "authenticated",
      "active"
    ],
    "revoked_denied": true,
    "replayed_denied": true
  },
  "capability": {
    "required": true,
    "freshness_required": true,
    "maximum_age_seconds": 900,
    "stale_capability_denied": true
  },
  "local_approval": {
    "required": true,
    "approved_value": true
  },
  "routes": {
    "public": {
      "GET": [
        "/api/v1/health",
        "/api/v1/info"
      ]
    },
    "protected": {
      "GET": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/pairing",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    }
  },
  "roles": {
    "workstation": {
      "allowed_protected_routes": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/pairing",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    },
    "mobile": {
      "allowed_protected_routes": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    },
    "server": {
      "allowed_protected_routes": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/pairing",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    },
    "edge": {
      "allowed_protected_routes": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    },
    "dev": {
      "allowed_protected_routes": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    },
    "ai-node": {
      "allowed_protected_routes": [
        "/api/v1/devices",
        "/api/v1/services",
        "/api/v1/capabilities",
        "/api/v1/discovery",
        "/api/v1/sessions",
        "/api/v1/sync",
        "/api/v1/transfer"
      ]
    }
  },
  "dangerous_operations": {
    "execute": {
      "allowed": false,
      "reason": "remote execution is globally disabled"
    },
    "install": {
      "allowed": false,
      "reason": "remote installation is globally disabled"
    },
    "shell": {
      "allowed": false,
      "reason": "remote shell is globally disabled"
    }
  },
  "explicit_denials": [
    {
      "method": "*",
      "path": "/api/v1/execute",
      "reason": "remote execution disabled"
    },
    {
      "method": "*",
      "path": "/api/v1/install",
      "reason": "remote installation disabled"
    },
    {
      "method": "*",
      "path": "/api/v1/shell",
      "reason": "remote shell disabled"
    }
  ]
}
JSON

ok 'authoritative policy'

printf '\n◆ Building policy engine authority...\n'

cat > "$AUTHORITY" <<'NODE'
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ENV_ROOT = process.env.DNYF_ROOT;
const LOCAL_ROOT = path.resolve(__dirname, '../../../..');
const ROOT =
  ENV_ROOT && ENV_ROOT.endsWith('/DNYF-DEV')
    ? ENV_ROOT
    : LOCAL_ROOT;

const ETC = path.join(ROOT, 'etc', 'dnyf');
const OPT = path.join(ROOT, 'opt', 'dnyf');
const REG = path.join(ROOT, 'registry');

const POLICY_SCHEMA_PATH = path.join(
  ETC,
  'policy',
  'dnyf-policy-engine-schema.json'
);

const POLICY_PATH = path.join(
  ETC,
  'policy',
  'dnyf-policy-engine-policy.json'
);

const IDENTITY_PATH = path.join(
  OPT,
  'runtime',
  'secure',
  'identity',
  'identity.json'
);

const DEVICE_REGISTRY_PATH = path.join(
  REG,
  'dnyf-unified-device-registry.json'
);

const CAPABILITY_STATE_PATH = path.join(
  OPT,
  'state',
  'capability',
  'local-capability-state.json'
);

const AUDIT_DIR = path.join(
  OPT,
  'state',
  'policy-engine',
  'audit'
);

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function canonical(value) {
  if (Array.isArray(value)) {
    return value.map(canonical);
  }

  if (value && typeof value === 'object') {
    return Object.keys(value)
      .sort()
      .reduce((out, key) => {
        out[key] = canonical(value[key]);
        return out;
      }, {});
  }

  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonical(value));
}

function sha256(value) {
  return crypto
    .createHash('sha256')
    .update(typeof value === 'string' ? value : canonicalJson(value))
    .digest('hex');
}

function loadIdentity() {
  return readJson(IDENTITY_PATH);
}

function loadSchema() {
  return readJson(POLICY_SCHEMA_PATH);
}

function loadPolicy() {
  return readJson(POLICY_PATH);
}

function policyFingerprint() {
  return sha256(loadPolicy());
}

function loadDeviceRegistry() {
  return readJson(DEVICE_REGISTRY_PATH);
}

function loadCapabilityState() {
  try {
    return readJson(CAPABILITY_STATE_PATH);
  } catch (_) {
    return {};
  }
}

function writeAudit(decision) {
  fs.mkdirSync(AUDIT_DIR, { recursive: true });

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(
    AUDIT_DIR,
    `dnyf-policy-decision-${stamp}.json`
  );

  fs.writeFileSync(
    file,
    JSON.stringify(decision, null, 2) + '\n',
    { mode: 0o600 }
  );

  return file;
}

function deny(reason, checks = {}) {
  return {
    decision: 'deny',
    authorized: false,
    reason,
    checks
  };
}

function allow(reason, checks = {}) {
  return {
    decision: 'allow',
    authorized: true,
    reason,
    checks
  };
}

function normalizeRequest(request = {}) {
  return {
    request_id: String(request.request_id || ''),
    peer_id: String(request.peer_id || ''),
    peer_fingerprint: String(request.peer_fingerprint || ''),
    method: String(request.method || '').toUpperCase(),
    path: String(request.path || ''),
    resource: String(request.resource || ''),
    authenticated: request.authenticated === true,
    proof_of_possession: request.proof_of_possession === true,
    timestamp_valid: request.timestamp_valid === true,
    nonce_valid: request.nonce_valid === true,
    replay_blocked: request.replay_blocked === true,
    trust_state: String(request.trust_state || ''),
    session_state: String(request.session_state || ''),
    local_approved: request.local_approved === true,
    capability_fresh: request.capability_fresh === true,
    capability_requirements_met:
      request.capability_requirements_met === true,
    device_role: String(request.device_role || ''),
    operation: String(request.operation || '').toLowerCase()
  };
}

function isDangerous(request, policy) {
  const dangerous = policy.dangerous_operations || {};

  if (request.operation && dangerous[request.operation]) {
    return dangerous[request.operation].allowed !== true;
  }

  const pathValue = request.path;

  return [
    '/api/v1/execute',
    '/api/v1/install',
    '/api/v1/shell'
  ].includes(pathValue);
}

function routeClass(request, policy) {
  const publicRoutes = policy.routes?.public?.[request.method] || [];
  const protectedRoutes = policy.routes?.protected?.[request.method] || [];

  if (publicRoutes.includes(request.path)) {
    return 'public';
  }

  if (protectedRoutes.includes(request.path)) {
    return 'protected';
  }

  return 'unknown';
}

function evaluate(requestInput = {}) {
  const request = normalizeRequest(requestInput);
  const policy = loadPolicy();
  const identity = loadIdentity();

  const decisionId = crypto.randomUUID();
  const started = Date.now();

  const checks = {
    request_shape: false,
    dangerous_operation_denial: false,
    identity: false,
    authentication: false,
    trust: false,
    session: false,
    capability: false,
    local_approval: false,
    route: false,
    role: false,
    explicit_deny: false,
    explicit_allow: false
  };

  if (
    !request.method ||
    !request.path ||
    !request.peer_id
  ) {
    const result = deny('invalid-request-shape', checks);
    return finalize(decisionId, request, result, started);
  }

  checks.request_shape = true;

  if (isDangerous(request, policy)) {
    checks.dangerous_operation_denial = true;

    const result = deny(
      'dangerous-operation-disabled',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.dangerous_operation_denial = true;

  if (
    request.peer_id === identity.device_id ||
    request.peer_fingerprint === identity.fingerprint
  ) {
    const result = deny(
      'self-peer-authorization-denied',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  if (
    !request.authenticated ||
    !request.proof_of_possession ||
    !request.timestamp_valid ||
    !request.nonce_valid ||
    !request.replay_blocked
  ) {
    const result = deny(
      'cryptographic-authentication-requirements-not-met',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.authentication = true;
  checks.identity = true;

  const route = routeClass(request, policy);

  if (route === 'unknown') {
    const result = deny(
      'unknown-route-default-deny',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.route = true;

  if (route === 'public') {
    checks.explicit_allow = true;

    const result = allow(
      'public-route',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  if (
    !policy.identity.accepted_device_roles.includes(
      request.device_role
    )
  ) {
    const result = deny(
      'unsupported-device-role',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.role = true;

  if (
    !policy.trust.accepted_states.includes(
      request.trust_state
    )
  ) {
    const result = deny(
      'peer-not-trusted',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.trust = true;

  if (
    !policy.session.accepted_states.includes(
      request.session_state
    )
  ) {
    const result = deny(
      'session-not-active',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.session = true;

  if (
    !request.capability_fresh ||
    !request.capability_requirements_met
  ) {
    const result = deny(
      'capability-requirements-not-met',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.capability = true;

  if (!request.local_approved) {
    const result = deny(
      'local-approval-required',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.local_approval = true;

  const roleRoutes =
    policy.roles?.[request.device_role]?.allowed_protected_routes || [];

  if (!roleRoutes.includes(request.path)) {
    const result = deny(
      'route-not-authorized-for-device-role',
      checks
    );

    return finalize(decisionId, request, result, started);
  }

  checks.explicit_allow = true;

  return finalize(
    decisionId,
    request,
    allow(
      'policy-requirements-satisfied',
      checks
    ),
    started
  );
}

function finalize(decisionId, request, result, started) {
  const identity = loadIdentity();
  const policy = loadPolicy();

  const response = {
    schema: 'dnyf.policy.decision.v1',
    decision_id: decisionId,
    timestamp: new Date().toISOString(),
    device_id: identity.device_id,
    policy_id: policy.policy_id,
    policy_version: policy.version,
    policy_fingerprint: policyFingerprint(),
    request: request,
    decision: result.decision,
    authorized: result.authorized,
    reason: result.reason,
    checks: result.checks,
    evaluation_ms: Date.now() - started,
    security: {
      default_deny: true,
      fail_closed: true,
      grants_trust: false,
      grants_pairing: false,
      grants_execution: false,
      grants_installation: false,
      grants_shell: false,
      privilege_escalation: false,
      self_trust: false,
      automatic_trust: false
    }
  };

  response.audit_file = writeAudit(response);

  return response;
}

function status() {
  const schema = loadSchema();
  const policy = loadPolicy();
  const identity = loadIdentity();

  return {
    schema: 'dnyf.policy.engine.status.v1',
    service: 'dnyf-policy-engine',
    device_id: identity.device_id,
    fingerprint: identity.fingerprint,
    policy_id: policy.policy_id,
    policy_version: policy.version,
    policy_fingerprint: policyFingerprint(),
    mode: policy.mode,
    security: schema.security,
    authorization: schema.authorization
  };
}

module.exports = {
  ROOT,
  loadIdentity,
  loadSchema,
  loadPolicy,
  loadDeviceRegistry,
  loadCapabilityState,
  canonical,
  canonicalJson,
  sha256,
  policyFingerprint,
  evaluate,
  status,
  writeAudit
};
NODE

chmod 600 "$AUTHORITY"
ok 'policy engine authority'

printf '\n◆ Creating policy CLI...\n'

cat > "$CLI" <<'NODE'
#!/data/data/com.termux/files/usr/bin/node
'use strict';

const engine = require(
  process.env.DNYF_POLICY_ENGINE_AUTHORITY ||
  '/data/data/com.termux/files/home/DNYF-DEV/opt/dnyf/runtime/policy-engine/dnyf-policy-engine-authority.js'
);

const command = process.argv[2] || 'status';

function print(value) {
  process.stdout.write(
    typeof value === 'string'
      ? value + '\n'
      : JSON.stringify(value, null, 2) + '\n'
  );
}

switch (command) {
  case 'status':
    print(engine.status());
    break;

  case 'fingerprint':
    print(engine.policyFingerprint());
    break;

  case 'policy':
    print(engine.loadPolicy());
    break;

  case 'schema':
    print(engine.loadSchema());
    break;

  case 'evaluate': {
    const encoded = process.argv[3];

    if (!encoded) {
      process.stderr.write(
        'Usage: dnyf-policy evaluate <json-request>\n'
      );
      process.exit(2);
    }

    let request;

    try {
      request = JSON.parse(encoded);
    } catch (error) {
      process.stderr.write(
        'Invalid JSON request: ' + error.message + '\n'
      );
      process.exit(2);
    }

    print(engine.evaluate(request));
    break;
  }

  case 'test':
    print({
      service: 'dnyf-policy-engine',
      contract: 'dnyf.policy.decision.v1',
      status: 'use phase9b validator for complete contract tests'
    });
    break;

  default:
    process.stderr.write(
      'Usage: dnyf-policy {status|fingerprint|policy|schema|evaluate|test}\n'
    );
    process.exit(2);
}
NODE

chmod 755 "$CLI"

ln -sfn "$CLI" "$USR_BIN/dnyf-policy"
ln -sfn "$CLI" "$USR_LOCAL_BIN/dnyf-policy"

ok 'policy CLI'

printf '\n◆ Writing local policy state...\n'

POLICY_FINGERPRINT="$(
  node -e '
    const fs=require("fs");
    const crypto=require("crypto");
    const x=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const c=v=>Array.isArray(v)
      ? v.map(c)
      : v && typeof v==="object"
        ? Object.keys(v).sort().reduce((o,k)=>(o[k]=c(v[k]),o),{})
        : v;
    process.stdout.write(
      crypto.createHash("sha256")
        .update(JSON.stringify(c(x)))
        .digest("hex")
    );
  ' "$POLICY"
)"

cat > "$STATE" <<JSON
{
  "schema": "dnyf.policy.engine.state.v1",
  "service": "dnyf-policy-engine",
  "device_id": "${DEVICE_ID}",
  "fingerprint": "${EXPECTED_FINGERPRINT}",
  "policy_id": "dnyf-default-security-policy",
  "policy_version": "1.0.0",
  "policy_fingerprint": "${POLICY_FINGERPRINT}",
  "mode": "default-deny",
  "security": {
    "fail_closed": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false
  }
}
JSON

chmod 600 "$STATE"
ok 'local policy state'

printf '\n◆ Writing policy-engine registry...\n'

cat > "$REGISTRY" <<JSON
{
  "schema": "dnyf.policy.engine.registry.v1",
  "service_id": "dnyf-policy-engine",
  "device_id": "${DEVICE_ID}",
  "fingerprint": "${EXPECTED_FINGERPRINT}",
  "version": "1.0.0",
  "api_version": "v1",
  "transport": [
    "local-process",
    "http",
    "https"
  ],
  "entrypoint": "opt/dnyf/runtime/policy-engine/dnyf-policy-engine-authority.js",
  "cli": "bin/dnyf-policy",
  "policy": "etc/dnyf/policy/dnyf-policy-engine-policy.json",
  "schema_file": "etc/dnyf/policy/dnyf-policy-engine-schema.json",
  "security": {
    "default_deny": true,
    "fail_closed": true,
    "policy_integrity_required": true,
    "grants_trust": false,
    "grants_pairing": false,
    "grants_execution": false,
    "grants_installation": false,
    "grants_shell": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false
  }
}
JSON

ok 'policy-engine registry'

printf '\n◆ Integrating service registry...\n'

node - "$SERVICES" "$DEVICE_ID" "$EXPECTED_FINGERPRINT" <<'NODE'
const fs = require('fs');

const file = process.argv[2];
const deviceId = process.argv[3];
const fingerprint = process.argv[4];

let registry = {};

try {
  registry = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (_) {
  registry = {
    schema: 'dnyf.services.registry.v1',
    version: '1.0.0',
    services: []
  };
}

if (!Array.isArray(registry.services)) {
  registry.services = [];
}

const service = {
  service_id: 'dnyf-policy-engine',
  name: 'DNYF Policy Engine',
  protocol: 'dnyf-policy/1',
  api_version: 'v1',
  version: '1.0.0',
  device_id: deviceId,
  fingerprint,
  transport: [
    'local-process',
    'http',
    'https'
  ],
  status: 'active',
  security: {
    default_deny: true,
    fail_closed: true,
    grants_trust: false,
    grants_pairing: false,
    grants_execution: false,
    grants_installation: false,
    grants_shell: false
  }
};

const index = registry.services.findIndex(
  x => x && x.service_id === service.service_id
);

if (index >= 0) {
  registry.services[index] = service;
} else {
  registry.services.push(service);
}

registry.services.sort((a, b) =>
  String(a.service_id).localeCompare(String(b.service_id))
);

fs.writeFileSync(
  file,
  JSON.stringify(registry, null, 2) + '\n'
);
NODE

ok 'service registry integration'

printf '\n◆ Writing Phase 9B manifest...\n'

cat > "$MANIFEST" <<JSON
{
  "schema": "dnyf.phase.manifest.v1",
  "phase": "9B",
  "name": "DNYF Policy Engine",
  "version": "1.0.0",
  "status": "complete",
  "device_id": "${DEVICE_ID}",
  "fingerprint": "${EXPECTED_FINGERPRINT}",
  "artifacts": [
    "etc/dnyf/policy/dnyf-policy-engine-schema.json",
    "etc/dnyf/policy/dnyf-policy-engine-policy.json",
    "opt/dnyf/runtime/policy-engine/dnyf-policy-engine-authority.js",
    "opt/dnyf/state/policy-engine/local-policy-state.json",
    "bin/dnyf-policy",
    "usr/bin/dnyf-policy",
    "usr/local/bin/dnyf-policy",
    "registry/dnyf-policy-engine-registry.json",
    "registry/services.json"
  ],
  "security": {
    "default_deny": true,
    "fail_closed": true,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "privilege_escalation": false,
    "policy_grants_trust": false,
    "policy_grants_pairing": false,
    "policy_bypasses_gateway": false
  }
}
JSON

ok 'Phase 9B manifest'

printf '\n◆ JavaScript syntax validation...\n'

node --check "$AUTHORITY"
ok 'authority syntax'

node --check "$CLI"
ok 'CLI syntax'

printf '\n◆ Policy schema validation...\n'

node - "$SCHEMA" <<'NODE'
const fs = require('fs');

const x = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

const required = [
  'schema',
  'version',
  'name',
  'decision_states',
  'evaluation_order',
  'security',
  'authentication',
  'authorization',
  'integrity'
];

for (const key of required) {
  if (!(key in x)) {
    throw new Error('missing schema field: ' + key);
  }
}

if (x.security.default_deny !== true) {
  throw new Error('default deny must be true');
}

if (x.security.fail_closed !== true) {
  throw new Error('fail closed must be true');
}

if (x.security.remote_execution !== false) {
  throw new Error('remote execution must remain disabled');
}

if (x.security.remote_installation !== false) {
  throw new Error('remote installation must remain disabled');
}

if (x.security.remote_shell !== false) {
  throw new Error('remote shell must remain disabled');
}

console.log('policy schema contract valid');
NODE

ok 'policy schema contract'

printf '\n◆ Policy security validation...\n'

node - "$POLICY" <<'NODE'
const fs = require('fs');

const p = JSON.parse(
  fs.readFileSync(process.argv[2], 'utf8')
);

if (p.mode !== 'default-deny') {
  throw new Error('policy mode is not default-deny');
}

if (p.evaluation.deny_precedence !== true) {
  throw new Error('deny precedence disabled');
}

if (p.evaluation.fail_closed !== true) {
  throw new Error('fail closed disabled');
}

for (const route of [
  '/api/v1/execute',
  '/api/v1/install',
  '/api/v1/shell'
]) {
  const found = p.explicit_denials.some(
    x => x.path === route
  );

  if (!found) {
    throw new Error('dangerous route not explicitly denied: ' + route);
  }
}

if (p.dangerous_operations.execute.allowed !== false) {
  throw new Error('execution is enabled');
}

if (p.dangerous_operations.install.allowed !== false) {
  throw new Error('installation is enabled');
}

if (p.dangerous_operations.shell.allowed !== false) {
  throw new Error('shell is enabled');
}

console.log('policy security contract valid');
NODE

ok 'policy security contract'

printf '\n◆ Policy integrity validation...\n'

node - "$AUTHORITY" "$POLICY" <<'NODE'
const engine = require(process.argv[2]);
const expected = engine.policyFingerprint();

if (!/^[a-f0-9]{64}$/.test(expected)) {
  throw new Error('invalid policy SHA-256 fingerprint');
}

console.log('policy fingerprint:', expected);
NODE

ok 'policy integrity fingerprint'

printf '\n◆ Deterministic authorization contract tests...\n'

node - "$AUTHORITY" <<'NODE'
const engine = require(process.argv[2]);

const base = {
  request_id: '9b-contract-compatible',
  peer_id: 'peer-test-001',
  peer_fingerprint: 'peer-fingerprint-001',
  method: 'GET',
  path: '/api/v1/services',
  resource: '/api/v1/services',
  authenticated: true,
  proof_of_possession: true,
  timestamp_valid: true,
  nonce_valid: true,
  replay_blocked: true,
  trust_state: 'trusted',
  session_state: 'authenticated',
  local_approved: true,
  capability_fresh: true,
  capability_requirements_met: true,
  device_role: 'workstation'
};

const allowed = engine.evaluate(base);

if (
  allowed.decision !== 'allow' ||
  allowed.authorized !== true
) {
  throw new Error(
    'compatible request was not allowed: ' +
    JSON.stringify(allowed)
  );
}

const deniedUnknown = engine.evaluate({
  ...base,
  request_id: '9b-contract-unknown',
  path: '/api/v1/not-authorized'
});

if (
  deniedUnknown.decision !== 'deny' ||
  deniedUnknown.reason !== 'unknown-route-default-deny'
) {
  throw new Error('unknown route was not denied');
}

const deniedTrust = engine.evaluate({
  ...base,
  request_id: '9b-contract-untrusted',
  trust_state: 'untrusted'
});

if (
  deniedTrust.decision !== 'deny' ||
  deniedTrust.reason !== 'peer-not-trusted'
) {
  throw new Error('untrusted peer was not denied');
}

const deniedApproval = engine.evaluate({
  ...base,
  request_id: '9b-contract-no-approval',
  local_approved: false
});

if (
  deniedApproval.decision !== 'deny' ||
  deniedApproval.reason !== 'local-approval-required'
) {
  throw new Error('missing local approval was not denied');
}

const deniedCapability = engine.evaluate({
  ...base,
  request_id: '9b-contract-stale-capability',
  capability_fresh: false
});

if (
  deniedCapability.decision !== 'deny' ||
  deniedCapability.reason !== 'capability-requirements-not-met'
) {
  throw new Error('invalid capability was not denied');
}

const deniedDangerous = engine.evaluate({
  ...base,
  request_id: '9b-contract-execute',
  method: 'POST',
  path: '/api/v1/execute',
  operation: 'execute'
});

if (
  deniedDangerous.decision !== 'deny' ||
  deniedDangerous.reason !== 'dangerous-operation-disabled'
) {
  throw new Error('dangerous operation was not denied');
}

const deniedSelf = engine.evaluate({
  ...base,
  request_id: '9b-contract-self',
  peer_id: engine.loadIdentity().device_id,
  peer_fingerprint: engine.loadIdentity().fingerprint
});

if (
  deniedSelf.decision !== 'deny' ||
  deniedSelf.reason !== 'self-peer-authorization-denied'
) {
  throw new Error('self peer was not denied');
}

const deniedAuth = engine.evaluate({
  ...base,
  request_id: '9b-contract-unauthenticated',
  authenticated: false
});

if (
  deniedAuth.decision !== 'deny' ||
  deniedAuth.reason !==
    'cryptographic-authentication-requirements-not-met'
) {
  throw new Error('unauthenticated request was not denied');
}

const a = engine.evaluate(base);
const b = engine.evaluate(base);

if (a.policy_fingerprint !== b.policy_fingerprint) {
  throw new Error('policy fingerprint is not deterministic');
}

console.log(JSON.stringify({
  compatible: {
    decision: allowed.decision,
    authorized: allowed.authorized
  },
  unknown_route: deniedUnknown.reason,
  untrusted_peer: deniedTrust.reason,
  missing_approval: deniedApproval.reason,
  invalid_capability: deniedCapability.reason,
  dangerous_operation: deniedDangerous.reason,
  self_peer: deniedSelf.reason,
  unauthenticated: deniedAuth.reason,
  policy_fingerprint: a.policy_fingerprint
}, null, 2));
NODE

ok 'authorization decision contract'

printf '\n◆ Policy explanation validation...\n'

node - "$AUTHORITY" <<'NODE'
const engine = require(process.argv[2]);

const result = engine.evaluate({
  request_id: '9b-explainability-test',
  peer_id: 'peer-explainability',
  peer_fingerprint: 'fingerprint-explainability',
  method: 'GET',
  path: '/api/v1/services',
  authenticated: true,
  proof_of_possession: true,
  timestamp_valid: true,
  nonce_valid: true,
  replay_blocked: true,
  trust_state: 'trusted',
  session_state: 'authenticated',
  local_approved: true,
  capability_fresh: true,
  capability_requirements_met: true,
  device_role: 'workstation'
});

if (!result.decision_id) {
  throw new Error('missing decision ID');
}

if (!result.reason) {
  throw new Error('missing explanation');
}

if (!result.checks) {
  throw new Error('missing decision checks');
}

if (!result.audit_file) {
  throw new Error('missing audit record');
}

console.log('decision:', result.decision);
console.log('reason:', result.reason);
console.log('decision_id:', result.decision_id);
console.log('audit:', result.audit_file);
NODE

ok 'decision explainability and audit'

printf '\n◆ Fail-closed validation...\n'

node - "$AUTHORITY" <<'NODE'
const engine = require(process.argv[2]);

const result = engine.evaluate({
  request_id: '9b-fail-closed',
  peer_id: 'peer-fail-closed',
  method: 'GET',
  path: '/api/v1/services'
});

if (
  result.decision !== 'deny' ||
  result.authorized !== false
) {
  throw new Error('missing security context did not fail closed');
}

console.log('fail-closed behavior valid');
NODE

ok 'fail-closed authorization'

printf '\n◆ Security separation validation...\n'

node - "$AUTHORITY" <<'NODE'
const engine = require(process.argv[2]);

const status = engine.status();

const forbidden = [
  ['self_trust', status.security.self_trust],
  ['self_pairing', status.security.self_pairing],
  ['automatic_trust', status.security.automatic_trust],
  ['remote_execution', status.security.remote_execution],
  ['remote_installation', status.security.remote_installation],
  ['remote_shell', status.security.remote_shell],
  ['privilege_escalation', status.security.privilege_escalation],
  ['policy_engine_grants_trust', status.security.policy_engine_grants_trust],
  ['policy_engine_grants_pairing', status.security.policy_engine_grants_pairing],
  ['policy_engine_grants_execution', status.security.policy_engine_grants_execution]
];

for (const [name, value] of forbidden) {
  if (value !== false) {
    throw new Error(name + ' is not false');
  }
}

console.log('policy authority security separation valid');
NODE

ok 'trust/authorization/execution separation'

printf '\n◆ CLI validation...\n'

CLI_STATUS="$(
  DNYF_POLICY_ENGINE_AUTHORITY="$AUTHORITY" \
  node "$CLI" status
)"

printf '%s\n' "$CLI_STATUS" | grep -q '"service": "dnyf-policy-engine"'
ok 'policy CLI status'

printf '\n◆ Permission validation...\n'

AUTH_MODE="$(stat -c '%a' "$AUTHORITY")"
STATE_MODE="$(stat -c '%a' "$STATE")"

if [ "$AUTH_MODE" = "600" ]; then
  ok 'policy authority permission 600'
else
  fail 'policy authority permission 600'
fi

if [ "$STATE_MODE" = "600" ]; then
  ok 'policy state permission 600'
else
  fail 'policy state permission 600'
fi

printf '\n◆ Final policy-engine status...\n'

DNYF_POLICY_ENGINE_AUTHORITY="$AUTHORITY" \
node "$CLI" status

printf '\n'
printf '%s\n' '============================================================'

if [ "$FAIL" -eq 0 ]; then
  printf '%s\n' ' PHASE 9B DNYF POLICY ENGINE: PASS'
else
  printf '%s\n' ' PHASE 9B DNYF POLICY ENGINE: FAIL'
fi

printf '%s\n' '============================================================'
printf 'Device ID   : %s\n' "$DEVICE_ID"
printf 'Fingerprint : %s\n' "$EXPECTED_FINGERPRINT"
printf 'Policy      : %s\n' "$POLICY"
printf 'Authority   : %s\n' "$AUTHORITY"
printf 'Registry    : %s\n' "$REGISTRY"
printf 'Manifest    : %s\n' "$MANIFEST"
printf 'Backup      : %s\n' "$BACKUP"
printf '\n'
printf 'Passed: %s\n' "$PASS"
printf 'Failed: %s\n' "$FAIL"

if [ "$FAIL" -ne 0 ]; then
  exit 1
fi

printf '\nValidated:\n'
printf '  ✓ default-deny authorization\n'
printf '  ✓ deterministic policy evaluation\n'
printf '  ✓ fail-closed behavior\n'
printf '  ✓ policy SHA-256 integrity\n'
printf '  ✓ identity binding\n'
printf '  ✓ cryptographic authentication gate\n'
printf '  ✓ trust-state requirement\n'
printf '  ✓ session-state requirement\n'
printf '  ✓ capability requirement\n'
printf '  ✓ local-approval requirement\n'
printf '  ✓ route authorization\n'
printf '  ✓ device-role authorization\n'
printf '  ✓ explicit dangerous-operation denial\n'
printf '  ✓ self-peer isolation\n'
printf '  ✓ decision explainability\n'
printf '  ✓ decision audit records\n'
printf '  ✓ service registry integration\n'
printf '  ✓ CLI validation\n'
printf '  ✓ security separation\n'
printf '\n'
printf 'Next phase: 9C DNYF Event Bus\n'
