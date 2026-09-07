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
