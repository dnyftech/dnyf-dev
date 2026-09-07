'use strict';

const fs = require('fs');
const crypto = require('crypto');
const os = require('os');

const ROOT = process.env.DNYF_ROOT || `${process.env.HOME}/DNYF-DEV`;

const PATHS = {
  identity: `${ROOT}/opt/dnyf/runtime/secure/identity/identity.json`,
  platform: `${ROOT}/etc/dnyf/platform/dnyf-runtime-platform.json`,
  capabilities: `${ROOT}/etc/dnyf/capabilities/dnyf-runtime-capabilities.json`,
  registry: `${ROOT}/registry/dnyf-unified-device-registry.json`,
  schema: `${ROOT}/etc/dnyf/capability/dnyf-capability-negotiation-schema.json`,
  policy: `${ROOT}/etc/dnyf/capability/dnyf-capability-negotiation-policy.json`,
  cache: `${ROOT}/opt/dnyf/state/capability/peer-cache`
};

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

function normalizeList(value) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map(String))].sort();
}

function firstDefined(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null) return value;
  }
  return undefined;
}

function loadLocal() {
  const identity = readJson(PATHS.identity);
  const platform = readJson(PATHS.platform);
  const capabilities = readJson(PATHS.capabilities);
  const registry = readJson(PATHS.registry);

  const registryDevice =
    registry.devices?.[identity.device_id] ||
    registry.devices?.[String(identity.device_id).toLowerCase()] ||
    null;

  return {
    identity,
    platform,
    capabilities,
    registry,
    registryDevice
  };
}

function platformValue(platform, key, fallback) {
  return firstDefined(
    platform?.[key],
    platform?.platform?.[key],
    platform?.runtime?.[key],
    fallback
  );
}

function capabilityValue(capabilities, key, fallback) {
  return firstDefined(
    capabilities?.[key],
    capabilities?.capabilities?.[key],
    capabilities?.runtime?.[key],
    fallback
  );
}

function buildOffer() {
  const local = loadLocal();
  const { identity, platform, capabilities, registryDevice } = local;

  const architecture = String(
    firstDefined(
      platformValue(platform, 'architecture'),
      platformValue(platform, 'arch'),
      process.arch
    )
  ).toLowerCase();

  const osName = String(
    firstDefined(
      platformValue(platform, 'platform'),
      platformValue(platform, 'os'),
      process.platform
    )
  ).toLowerCase();

  const runtime = String(
    firstDefined(
      platformValue(platform, 'runtime'),
      platformValue(platform, 'runtime_name'),
      'node'
    )
  ).toLowerCase();

  const logicalCores = Math.max(
    1,
    Number(
      firstDefined(
        capabilityValue(capabilities, 'normalized_logical_cores'),
        capabilityValue(capabilities, 'logical_cores'),
        os.cpus().length,
        1
      )
    ) || 1
  );

  const memoryBytes = Number(
    firstDefined(
      capabilityValue(capabilities, 'memory_bytes'),
      capabilityValue(capabilities, 'total_memory_bytes'),
      os.totalmem(),
      0
    )
  ) || 0;

  const tools = normalizeList(
    firstDefined(
      capabilityValue(capabilities, 'tools'),
      capabilityValue(capabilities, 'available_tools'),
      []
    )
  );

  const transports = {
    local_process: true,
    http: true,
    https: true,
    websocket: true,
    ipv4: true,
    ipv6: true
  };

  const security = {
    ed25519: true,
    sha256: true,
    cryptographic_authentication: true,
    proof_of_possession: true
  };

  const apiVersions = ['v1'];

  const executionClasses = [
    'local-process',
    'artifact-inspection',
    'metadata-analysis'
  ];

  const disabledExecution = {
    remote_execution: false,
    remote_installation: false,
    remote_shell: false
  };

  const serviceIds = normalizeList(
    registryDevice?.services?.service_ids ||
    registryDevice?.services ||
    []
  );

  const offer = {
    schema: 'dnyf.capability.offer.v1',
    protocol: 'dnyf-capability/1',
    version: '1.0.0',

    identity: {
      device_id: String(identity.device_id).toLowerCase(),
      fingerprint: String(identity.fingerprint).toLowerCase()
    },

    protocol_capabilities: {
      protocols: ['dnyf-capability/1'],
      versions: ['1.0.0'],
      api_versions: apiVersions
    },

    platform: {
      os: osName,
      architecture,
      runtime,
      node: process.version
    },

    transport: transports,

    security,

    services: {
      service_ids: serviceIds
    },

    resources: {
      logical_cores: logicalCores,
      memory_bytes: memoryBytes,
      memory_class:
        memoryBytes >= 8 * 1024 * 1024 * 1024 ? 'high' :
        memoryBytes >= 4 * 1024 * 1024 * 1024 ? 'medium-high' :
        memoryBytes >= 2 * 1024 * 1024 * 1024 ? 'medium' :
        'constrained'
    },

    workload: {
      execution_classes: executionClasses,
      remote_execution: false,
      remote_installation: false,
      remote_shell: false
    },

    tools,

    policy: {
      self_trust: false,
      self_pairing: false,
      automatic_trust: false,
      capability_exchange_grants_trust: false,
      capability_exchange_grants_authorization: false
    },

    freshness: {
      generated_at: new Date().toISOString(),
      max_age_seconds: 900
    }
  };

  offer.capability_fingerprint = sha256(offer);

  return offer;
}

function ensureOfferIntegrity(offer) {
  if (!offer || typeof offer !== 'object') {
    throw new Error('Capability offer is not an object');
  }

  if (offer.schema !== 'dnyf.capability.offer.v1') {
    throw new Error('Unsupported capability offer schema');
  }

  if (!offer.identity?.device_id) {
    throw new Error('Capability offer has no device ID');
  }

  if (!offer.identity?.fingerprint) {
    throw new Error('Capability offer has no fingerprint');
  }

  if (!offer.capability_fingerprint) {
    throw new Error('Capability offer has no fingerprint hash');
  }

  const expected = sha256({
    ...offer,
    capability_fingerprint: undefined
  });

  /*
   * Undefined properties are omitted by JSON.stringify.
   * This means the fingerprint is calculated over the offer
   * without the fingerprint field itself.
   */
  if (expected !== offer.capability_fingerprint) {
    throw new Error('Capability fingerprint mismatch');
  }

  return true;
}

function cloneWithoutFingerprint(offer) {
  const copy = JSON.parse(JSON.stringify(offer));
  delete copy.capability_fingerprint;
  return copy;
}

function fingerprintOffer(offer) {
  return sha256(cloneWithoutFingerprint(offer));
}

function refreshFingerprint(offer) {
  const copy = cloneWithoutFingerprint(offer);
  copy.capability_fingerprint = fingerprintOffer(copy);
  return copy;
}

function normalizeVersions(values) {
  return normalizeList(values).sort((a, b) => {
    const pa = a.replace(/^v/, '').split('.').map(Number);
    const pb = b.replace(/^v/, '').split('.').map(Number);

    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
      const x = pa[i] || 0;
      const y = pb[i] || 0;
      if (x !== y) return y - x;
    }

    return 0;
  });
}

function intersectLists(a, b) {
  const right = new Set(normalizeList(b));
  return normalizeList(a).filter(item => right.has(item));
}

function selectHighestCommonVersion(a, b) {
  const common = intersectLists(a, b);
  return normalizeVersions(common)[0] || null;
}

function selectTransport(local, remote) {
  const order = [
    'https',
    'websocket',
    'http',
    'local_process'
  ];

  for (const transport of order) {
    if (local?.[transport] === true && remote?.[transport] === true) {
      return transport;
    }
  }

  return null;
}

function negotiate(localOffer, remoteOffer) {
  ensureOfferIntegrity(localOffer);
  ensureOfferIntegrity(remoteOffer);

  const reasons = [];
  const warnings = [];

  if (
    localOffer.identity.device_id ===
    remoteOffer.identity.device_id
  ) {
    reasons.push('self-device-capability-exchange');
  }

  const commonProtocol = selectHighestCommonVersion(
    localOffer.protocol_capabilities?.versions || [],
    remoteOffer.protocol_capabilities?.versions || []
  );

  if (!commonProtocol) {
    reasons.push('no-common-protocol-version');
  }

  const commonApi = selectHighestCommonVersion(
    localOffer.protocol_capabilities?.api_versions || [],
    remoteOffer.protocol_capabilities?.api_versions || []
  );

  if (!commonApi) {
    reasons.push('no-common-api-version');
  }

  const transport = selectTransport(
    localOffer.transport,
    remoteOffer.transport
  );

  if (!transport) {
    reasons.push('no-common-transport');
  }

  const architectureCompatible =
    localOffer.platform?.architecture ===
    remoteOffer.platform?.architecture;

  const platformCompatible =
    localOffer.platform?.os ===
    remoteOffer.platform?.os ||
    (
      localOffer.platform?.os === 'linux' &&
      remoteOffer.platform?.os === 'android'
    ) ||
    (
      localOffer.platform?.os === 'android' &&
      remoteOffer.platform?.os === 'linux'
    );

  const commonExecution = intersectLists(
    localOffer.workload?.execution_classes || [],
    remoteOffer.workload?.execution_classes || []
  );

  const commonServices = intersectLists(
    localOffer.services?.service_ids || [],
    remoteOffer.services?.service_ids || []
  );

  const securityRequired = [
    'ed25519',
    'sha256',
    'cryptographic_authentication',
    'proof_of_possession'
  ];

  const missingSecurity = securityRequired.filter(
    key =>
      localOffer.security?.[key] !== true ||
      remoteOffer.security?.[key] !== true
  );

  if (missingSecurity.length) {
    reasons.push(
      `missing-required-security:${missingSecurity.join(',')}`
    );
  }

  if (!architectureCompatible) {
    warnings.push('architecture-mismatch');
  }

  if (!platformCompatible) {
    warnings.push('platform-mismatch');
  }

  const localMemory =
    Number(localOffer.resources?.memory_bytes || 0);

  const remoteMemory =
    Number(remoteOffer.resources?.memory_bytes || 0);

  const safeMemory = Math.min(
    localMemory || Number.MAX_SAFE_INTEGER,
    remoteMemory || Number.MAX_SAFE_INTEGER
  );

  const localCores =
    Math.max(1, Number(localOffer.resources?.logical_cores || 1));

  const remoteCores =
    Math.max(1, Number(remoteOffer.resources?.logical_cores || 1));

  const result = {
    schema: 'dnyf.capability.negotiation-result.v1',
    protocol: 'dnyf-capability/1',
    version: '1.0.0',

    local_device_id: localOffer.identity.device_id,
    remote_device_id: remoteOffer.identity.device_id,

    local_capability_fingerprint:
      localOffer.capability_fingerprint,

    remote_capability_fingerprint:
      remoteOffer.capability_fingerprint,

    compatible:
      reasons.length === 0,

    state:
      reasons.length === 0
        ? 'compatible'
        : 'incompatible',

    reasons,
    warnings,

    negotiated: {
      protocol_version: commonProtocol,
      api_version: commonApi,
      transport,
      architecture_compatible: architectureCompatible,
      platform_compatible: platformCompatible,

      execution_classes: commonExecution,
      service_ids: commonServices,

      resources: {
        logical_cores: Math.min(localCores, remoteCores),
        memory_bytes:
          safeMemory === Number.MAX_SAFE_INTEGER
            ? 0
            : safeMemory
      }
    },

    security: {
      authenticated_exchange_required: true,
      proof_of_possession_required: true,
      capability_exchange_grants_trust: false,
      capability_exchange_grants_authorization: false,
      remote_execution: false,
      remote_installation: false,
      remote_shell: false
    },

    negotiated_at: new Date().toISOString()
  };

  result.negotiation_fingerprint = sha256(result);

  return result;
}

function isFresh(offer, maxAgeSeconds = 900) {
  const generated =
    Date.parse(offer?.freshness?.generated_at || '');

  if (!Number.isFinite(generated)) return false;

  const age = (Date.now() - generated) / 1000;

  return age >= 0 && age <= maxAgeSeconds;
}

function cachePeerOffer(offer) {
  ensureOfferIntegrity(offer);

  const file =
    `${PATHS.cache}/${offer.identity.device_id}.json`;

  fs.mkdirSync(PATHS.cache, { recursive: true });

  const record = {
    schema: 'dnyf.capability.cache.v1',
    device_id: offer.identity.device_id,
    fingerprint: offer.identity.fingerprint,
    capability_fingerprint: offer.capability_fingerprint,
    cached_at: new Date().toISOString(),
    offer
  };

  fs.writeFileSync(
    file,
    JSON.stringify(record, null, 2) + '\n',
    { mode: 0o600 }
  );

  return file;
}

function loadCachedPeer(deviceId) {
  const file =
    `${PATHS.cache}/${String(deviceId).toLowerCase()}.json`;

  if (!fs.existsSync(file)) return null;

  return readJson(file);
}

function status() {
  const offer = buildOffer();

  return {
    ok: true,
    schema: 'dnyf.capability.status.v1',
    device_id: offer.identity.device_id,
    fingerprint: offer.identity.fingerprint,
    capability_fingerprint: offer.capability_fingerprint,
    architecture: offer.platform.architecture,
    platform: offer.platform.os,
    runtime: offer.platform.runtime,
    logical_cores: offer.resources.logical_cores,
    memory_bytes: offer.resources.memory_bytes,
    api_versions: offer.protocol_capabilities.api_versions,
    transports: Object.keys(offer.transport)
      .filter(k => offer.transport[k] === true),
    security: offer.security,
    policy: offer.policy
  };
}

module.exports = {
  PATHS,
  canonical,
  canonicalJson,
  sha256,
  loadLocal,
  buildOffer,
  ensureOfferIntegrity,
  fingerprintOffer,
  refreshFingerprint,
  negotiate,
  isFresh,
  cachePeerOffer,
  loadCachedPeer,
  status
};
