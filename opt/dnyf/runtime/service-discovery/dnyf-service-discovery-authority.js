'use strict';

const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const path = require('path');

const ROOT = process.env.DNYF_ROOT || path.resolve(
  process.env.HOME || process.cwd(),
  'DNYF-DEV'
);

const IDENTITY_FILE =
  path.join(ROOT,'opt/dnyf/runtime/secure/identity/identity.json');

const CAPABILITY_FILE =
  path.join(ROOT,'etc/dnyf/capabilities/dnyf-runtime-capabilities.json');

const CAPABILITY_OFFER =
  path.join(ROOT,'opt/dnyf/state/capability/local-capability-offer.json');

const SERVICE_REGISTRY =
  path.join(ROOT,'registry/services.json');

const POLICY_FILE =
  path.join(ROOT,'etc/dnyf/service-discovery/dnyf-service-discovery-policy.json');

const DISCOVERY_STATE =
  path.join(ROOT,'opt/dnyf/state/service-discovery/local-discovery-state.json');

const PEER_CACHE =
  path.join(ROOT,'opt/dnyf/state/service-discovery/peer-cache');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file,'utf8'));
}

function writeJson(file,value) {
  fs.mkdirSync(path.dirname(file),{recursive:true});
  fs.writeFileSync(file,JSON.stringify(value,null,2)+'\n',{mode:0o600});
}

function canonical(value) {
  if(Array.isArray(value)) return value.map(canonical);
  if(value && typeof value === 'object') {
    return Object.keys(value).sort().reduce((o,k)=>{
      o[k]=canonical(value[k]);
      return o;
    },{});
  }
  return value;
}

function canonicalJson(value) {
  return JSON.stringify(canonical(value));
}

function sha256(value) {
  return crypto.createHash('sha256')
    .update(typeof value === 'string' ? value : canonicalJson(value))
    .digest('hex');
}

function identity() {
  return readJson(IDENTITY_FILE);
}

function localCapabilities() {
  return readJson(CAPABILITY_FILE);
}

function localOffer() {
  return readJson(CAPABILITY_OFFER);
}

function policy() {
  return readJson(POLICY_FILE);
}

function loadLocalServices() {
  const registry = readJson(SERVICE_REGISTRY);

  if(Array.isArray(registry)) return registry;
  if(Array.isArray(registry.services)) return registry.services;

  return Object.entries(registry.services || {}).map(([id,value])=>({
    service_id:id,
    ...value
  }));
}

function normalizeTransportList(value) {
  if(!Array.isArray(value)) return [];
  return [...new Set(value.map(String))].sort();
}

function normalizeEndpoints(value) {
  if(!Array.isArray(value)) return [];

  return value
    .map(e => {
      if(typeof e === 'string') {
        return {
          address:e,
          network:'unknown',
          family:e.includes('[') ? 'ipv6' :
                 e.includes(':') ? 'ipv6' : 'ipv4'
        };
      }

      return {
        address:String(e.address || ''),
        network:String(e.network || 'unknown'),
        family:String(e.family || 'unknown'),
        port:e.port == null ? undefined : Number(e.port)
      };
    })
    .filter(e => e.address);
}

function detectNetworkInterfaces() {
  const interfaces = os.networkInterfaces();
  const addresses = [];

  for(const [name,items] of Object.entries(interfaces)) {
    for(const item of (items || [])) {
      if(item.internal) continue;

      const family = String(item.family).toLowerCase();
      const normalizedFamily =
        family.includes('6') ? 'ipv6' : 'ipv4';

      addresses.push({
        interface:name,
        address:item.address,
        family:normalizedFamily,
        internal:false
      });
    }
  }

  return addresses;
}

function inferServiceName(service) {
  return String(
    service.service_name ||
    service.name ||
    service.id ||
    service.service_id ||
    'dnyf-service'
  );
}

function inferServiceId(service) {
  return String(
    service.service_id ||
    service.id ||
    `dnyf-${inferServiceName(service).toLowerCase().replace(/[^a-z0-9]+/g,'-')}`
  );
}

function normalizeService(service, id, fingerprint) {
  const serviceId = inferServiceId(service);
  const name = inferServiceName(service);

  const transports = normalizeTransportList(
    service.transports ||
    service.transport ||
    ['http']
  );

  const endpoints = normalizeEndpoints(
    service.endpoints ||
    service.endpoint ||
    []
  );

  const capabilities =
    Array.isArray(service.capabilities)
      ? [...new Set(service.capabilities.map(String))].sort()
      : [];

  const protocol =
    service.protocol ||
    service.protocol_version ||
    'dnyf/1';

  const apiVersion =
    service.api_version ||
    'v1';

  const now = Date.now();
  const maxAge = 900;

  return {
    service_id:serviceId,
    service_name:name,
    device_id:id,
    device_fingerprint:fingerprint,
    protocol:String(protocol),
    api_version:String(apiVersion),
    transports,
    endpoints,
    capabilities,
    health:{
      state:String(service.health?.state || 'unknown'),
      last_check:String(service.health?.last_check || new Date(now).toISOString())
    },
    discovery:{
      source:'local-registry',
      authenticated_peer_binding:true,
      network_preference:['loopback','lan-ipv4','lan-ipv6','internet','relay'],
      mdns_compatible:true
    },
    last_seen:new Date(now).toISOString(),
    expires_at:new Date(now + maxAge*1000).toISOString(),
    security:{
      authenticated:true,
      proof_of_possession:true,
      grants_trust:false,
      grants_authorization:false,
      self_trust:false,
      self_pairing:false,
      automatic_trust:false,
      remote_execution:false,
      remote_installation:false,
      remote_shell:false
    }
  };
}

function enumerateLocalServices() {
  const id = identity();

  return loadLocalServices()
    .map(s=>normalizeService(
      s,
      String(id.device_id).toLowerCase(),
      String(id.fingerprint).toLowerCase()
    ));
}

function buildLocalRecord() {
  const id = identity();
  const cap = localCapabilities();
  const offer = localOffer();

  const services = enumerateLocalServices();

  return {
    schema:'dnyf.service.discovery.record.v1',
    generated_at:new Date().toISOString(),
    device:{
      device_id:String(id.device_id).toLowerCase(),
      fingerprint:String(id.fingerprint).toLowerCase(),
      public_key:id.public_key
    },
    platform:{
      platform:cap.platform || cap.os || process.platform,
      architecture:cap.architecture || process.arch
    },
    network:{
      addresses:detectNetworkInterfaces(),
      ipv4:true,
      ipv6:true,
      mdns_compatible:true
    },
    capability_fingerprint:
      offer.capability_fingerprint ||
      offer.fingerprint ||
      sha256(offer),
    services,
    security:{
      authenticated_discovery:true,
      proof_of_possession:true,
      discovery_grants_trust:false,
      discovery_grants_authorization:false,
      self_trust:false,
      self_pairing:false,
      automatic_trust:false,
      remote_execution:false,
      remote_installation:false,
      remote_shell:false
    }
  };
}

function saveLocalRecord() {
  const record = buildLocalRecord();
  writeJson(DISCOVERY_STATE,record);
  return record;
}

function loadLocalRecord() {
  return readJson(DISCOVERY_STATE);
}

function isFresh(record, now=Date.now()) {
  if(!record || !record.expires_at) return false;
  return new Date(record.expires_at).getTime() > now;
}

function common(a,b) {
  const A = new Set(a || []);
  return [...new Set(b || [])].filter(x=>A.has(x)).sort();
}

function negotiateService(localService, peerService) {
  if(!localService || !peerService) {
    return {
      compatible:false,
      reasons:['missing-service-record']
    };
  }

  const reasons = [];

  if(String(localService.protocol) !== String(peerService.protocol)) {
    reasons.push('no-common-protocol');
  }

  if(String(localService.api_version) !== String(peerService.api_version)) {
    reasons.push('no-common-api-version');
  }

  const transports = common(
    localService.transports,
    peerService.transports
  );

  if(!transports.length) {
    reasons.push('no-common-transport');
  }

  const capabilities = common(
    localService.capabilities,
    peerService.capabilities
  );

  const compatible = reasons.length === 0;

  return {
    compatible,
    service_id:localService.service_id,
    protocol:compatible ? localService.protocol : null,
    api_version:compatible ? localService.api_version : null,
    transports,
    common_capabilities:capabilities,
    reasons
  };
}

function cachePeer(record) {
  if(!record || !record.device || !record.device.device_id) {
    throw new Error('invalid peer discovery record');
  }

  const local = identity();
  const peerId = String(record.device.device_id).toLowerCase();

  if(peerId === String(local.device_id).toLowerCase()) {
    throw new Error('self discovery record rejected');
  }

  if(
    !record.device.fingerprint ||
    !record.device.public_key
  ) {
    throw new Error('peer identity binding required');
  }

  if(
    record.security?.authenticated_discovery !== true &&
    record.security?.authenticated !== true
  ) {
    throw new Error('authenticated discovery required');
  }

  if(
    record.security?.proof_of_possession !== true
  ) {
    throw new Error('proof of possession required');
  }

  if(!isFresh(record)) {
    throw new Error('stale discovery record');
  }

  const filename =
    path.join(PEER_CACHE,`${peerId}.json`);

  writeJson(filename,record);

  return filename;
}

function loadPeer(peerId) {
  const id = String(peerId).toLowerCase();

  if(id === String(identity().device_id).toLowerCase()) {
    throw new Error('self peer lookup rejected');
  }

  const file = path.join(PEER_CACHE,`${id}.json`);

  if(!fs.existsSync(file)) return null;

  const record = readJson(file);

  if(!isFresh(record)) return null;

  return record;
}

function buildRegistry() {
  const local = identity();
  const localRecord = loadLocalRecord();

  return {
    schema:'dnyf.service.discovery.registry.v1',
    version:'1.0.0',
    generated_at:new Date().toISOString(),
    local_device_id:String(local.device_id).toLowerCase(),
    local_fingerprint:String(local.fingerprint).toLowerCase(),
    discovery_policy:{
      offline_first:true,
      lan_preferred:true,
      internet_fallback:true,
      relay_fallback:true,
      ipv4:true,
      ipv6:true,
      mdns_compatible:true
    },
    security:{
      discovered_is_not_authenticated:true,
      authenticated_is_not_trusted:true,
      trusted_is_not_authorized:true,
      authorized_is_not_remote_execution:true,
      self_trust:false,
      self_pairing:false,
      automatic_trust:false,
      remote_execution:false,
      remote_installation:false,
      remote_shell:false
    },
    devices:[
      {
        device_id:String(local.device_id).toLowerCase(),
        fingerprint:String(local.fingerprint).toLowerCase(),
        public_key:local.public_key,
        source:'local-registry',
        authenticated:true,
        trusted:false,
        authorized:false,
        services:localRecord.services || []
      }
    ],
    peers:[]
  };
}

function saveRegistry() {
  const file =
    path.join(ROOT,'registry/dnyf-service-discovery-registry.json');

  const registry=buildRegistry();
  writeJson(file,registry);

  return registry;
}

function status() {
  const local=loadLocalRecord();

  return {
    schema:'dnyf.service.discovery.status.v1',
    device_id:String(identity().device_id).toLowerCase(),
    fingerprint:String(identity().fingerprint).toLowerCase(),
    services:(local.services || []).length,
    network_addresses:(local.network?.addresses || []).length,
    ipv4:true,
    ipv6:true,
    mdns_compatible:true,
    peer_cache_entries:fs.existsSync(PEER_CACHE)
      ? fs.readdirSync(PEER_CACHE).filter(x=>x.endsWith('.json')).length
      : 0,
    security:{
      self_trust:false,
      self_pairing:false,
      automatic_trust:false,
      remote_execution:false,
      remote_installation:false,
      remote_shell:false
    }
  };
}

module.exports={
  canonical,
  canonicalJson,
  sha256,
  identity,
  localCapabilities,
  localOffer,
  loadLocalServices,
  enumerateLocalServices,
  buildLocalRecord,
  saveLocalRecord,
  loadLocalRecord,
  detectNetworkInterfaces,
  isFresh,
  negotiateService,
  cachePeer,
  loadPeer,
  buildRegistry,
  saveRegistry,
  status
};
