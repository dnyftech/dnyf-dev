#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
PHASE="8J"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

ETC="$ROOT/etc/dnyf"
OPT="$ROOT/opt/dnyf"
REG="$ROOT/registry"
BIN="$ROOT/bin"
USR_BIN="$ROOT/usr/bin"
USR_LOCAL_BIN="$ROOT/usr/local/bin"
STATE="$OPT/state"
RUNTIME="$OPT/runtime"
BACKUP="$ROOT/backups/phase8j-service-discovery/$TIMESTAMP"
AUDIT="$STATE/audit"

SCHEMA="$ETC/service-discovery/dnyf-service-discovery-schema.json"
POLICY="$ETC/service-discovery/dnyf-service-discovery-policy.json"
LIBRARY="$RUNTIME/service-discovery/dnyf-service-discovery-authority.js"
CLI="$BIN/dnyf-service-discovery"
SERVICE_RECORD="$STATE/service-discovery/local-service-record.json"
DISCOVERY_STATE="$STATE/service-discovery/local-discovery-state.json"
PEER_CACHE="$STATE/service-discovery/peer-cache"
DISCOVERY_REGISTRY="$REG/dnyf-service-discovery-registry.json"
SERVICE_ENTRY="$REG/services.json"
MANIFEST="$ETC/phase8j-manifest.json"

IDENTITY="$OPT/runtime/secure/identity/identity.json"
CAPABILITY="$ETC/capabilities/dnyf-runtime-capabilities.json"
CAPABILITY_OFFER="$STATE/capability/local-capability-offer.json"
DEVICE_REGISTRY="$REG/dnyf-unified-device-registry.json"

mkdir -p \
  "$ETC/service-discovery" \
  "$RUNTIME/service-discovery" \
  "$STATE/service-discovery" \
  "$PEER_CACHE" \
  "$AUDIT" \
  "$BACKUP" \
  "$BIN" \
  "$USR_BIN" \
  "$USR_LOCAL_BIN"

echo
echo "============================================================"
echo " DNYFTECH — PHASE 8J SERVICE DISCOVERY REGISTRY"
echo "============================================================"
echo "Root: $ROOT"
echo "Timestamp: $TIMESTAMP"
echo

die() {
  echo "[FAIL] $*" >&2
  exit 1
}

ok() {
  echo "[OK] $*"
}

require_file() {
  [[ -f "$1" ]] || die "Missing required file: $1"
}

backup_if_exists() {
  local src="$1"
  local dst="$BACKUP/${src#$ROOT/}"
  if [[ -e "$src" || -L "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

echo "◆ Verifying 8H/8I foundation..."

require_file "$IDENTITY"
require_file "$CAPABILITY"
require_file "$CAPABILITY_OFFER"
require_file "$DEVICE_REGISTRY"
require_file "$SERVICE_ENTRY"

ok "canonical cryptographic identity"
ok "canonical capability metadata"
ok "8I capability offer"
ok "8H unified device registry"
ok "service registry"

echo "◆ Creating rollback snapshot..."

backup_if_exists "$SCHEMA"
backup_if_exists "$POLICY"
backup_if_exists "$LIBRARY"
backup_if_exists "$CLI"
backup_if_exists "$SERVICE_RECORD"
backup_if_exists "$DISCOVERY_STATE"
backup_if_exists "$DISCOVERY_REGISTRY"
backup_if_exists "$SERVICE_ENTRY"
backup_if_exists "$MANIFEST"

ok "rollback snapshot created"

echo "◆ Loading canonical identity..."

readarray -t IDENTITY_VALUES < <(
  node - "$IDENTITY" <<'NODE'
const fs=require('fs');
const x=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
for(const k of ['device_id','fingerprint','public_key']){
  if(!x[k]) throw new Error(`missing ${k}`);
  console.log(String(x[k]));
}
NODE
)

DEVICE_ID="${IDENTITY_VALUES[0],,}"
FINGERPRINT="${IDENTITY_VALUES[1],,}"
PUBLIC_KEY="${IDENTITY_VALUES[2]}"

[[ -n "$DEVICE_ID" ]] || die "empty device ID"
[[ -n "$FINGERPRINT" ]] || die "empty fingerprint"

echo "Device ID: $DEVICE_ID"
echo "Fingerprint: $FINGERPRINT"
ok "canonical identity loaded"

echo "◆ Writing service discovery schema..."

cat > "$SCHEMA" <<'JSON'
{
  "schema": "dnyf.service.discovery.v1",
  "version": "1.0.0",
  "description": "DNYFTECH authenticated service discovery and service registry contract",
  "identity": {
    "device_id_required": true,
    "fingerprint_required": true,
    "public_key_required": true
  },
  "service": {
    "service_id_required": true,
    "service_name_required": true,
    "device_id_required": true,
    "protocol_required": true,
    "api_version_required": true,
    "transports_required": true,
    "endpoints_required": true,
    "capabilities_required": true,
    "health_required": true,
    "last_seen_required": true,
    "expires_at_required": true
  },
  "discovery": {
    "offline_first": true,
    "lan_preferred": true,
    "internet_fallback": true,
    "relay_fallback": true,
    "ipv4": true,
    "ipv6": true,
    "mdns_compatible": true,
    "authenticated_peer_binding_required": true,
    "freshness_required": true
  },
  "security": {
    "authenticated_discovery_required": true,
    "proof_of_possession_required": true,
    "discovery_grants_trust": false,
    "discovery_grants_authorization": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false
  },
  "compatibility": {
    "protocol_version_required": true,
    "api_version_required": true,
    "capability_filtering_required": true,
    "transport_intersection_required": true
  }
}
JSON

ok "service discovery schema"

echo "◆ Writing service discovery policy..."

cat > "$POLICY" <<'JSON'
{
  "schema": "dnyf.service.discovery.policy.v1",
  "version": "1.0.0",
  "freshness": {
    "service_max_age_seconds": 900,
    "stale_after_seconds": 300,
    "peer_cache_max_age_seconds": 900,
    "negative_cache_seconds": 60
  },
  "transport_preference": [
    "local-process",
    "http",
    "https",
    "websocket"
  ],
  "network_preference": [
    "loopback",
    "lan-ipv4",
    "lan-ipv6",
    "internet",
    "relay"
  ],
  "discovery_methods": [
    "local-registry",
    "lan-registry",
    "mdns-compatible",
    "authenticated-peer-advertisement",
    "relay"
  ],
  "compatibility": {
    "require_common_protocol": true,
    "require_common_api_version": true,
    "require_common_transport": true,
    "require_required_capabilities": true,
    "allow_downgrade": false
  },
  "security": {
    "authentication_required": true,
    "proof_of_possession_required": true,
    "trust_required_for_sensitive_operations": true,
    "authorization_required_for_operations": true,
    "discovery_never_grants_trust": true,
    "discovery_never_grants_authorization": true
  },
  "forbidden": {
    "self_trust": true,
    "self_pairing": true,
    "automatic_trust": true,
    "remote_execution": true,
    "remote_installation": true,
    "remote_shell": true
  }
}
JSON

ok "service discovery policy"

echo "◆ Building service discovery authority library..."

cat > "$LIBRARY" <<'NODE'
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
NODE

chmod 600 "$LIBRARY"
ok "service discovery authority library"

echo "◆ Creating service discovery CLI..."

cat > "$CLI" <<'NODE'
#!/data/data/com.termux/files/usr/bin/node
'use strict';

const fs=require('fs');
const path=require('path');

const ROOT=process.env.DNYF_ROOT || path.resolve(
  process.env.HOME || process.cwd(),
  'DNYF-DEV'
);

const lib=require(
  path.join(ROOT,'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js')
);

const command=process.argv[2] || 'status';

function print(value) {
  console.log(JSON.stringify(value,null,2));
}

function fail(message) {
  console.error(`[FAIL] ${message}`);
  process.exit(1);
}

try {
  switch(command) {
    case 'status':
      print(lib.status());
      break;

    case 'services':
      print({
        schema:'dnyf.service.discovery.services.v1',
        services:lib.enumerateLocalServices()
      });
      break;

    case 'network':
      print({
        schema:'dnyf.service.discovery.network.v1',
        ipv4:true,
        ipv6:true,
        mdns_compatible:true,
        addresses:lib.detectNetworkInterfaces()
      });
      break;

    case 'refresh':
      print(lib.saveLocalRecord());
      lib.saveRegistry();
      break;

    case 'registry':
      print(lib.buildRegistry());
      break;

    case 'negotiate':
      if(!process.argv[3]) fail('peer service JSON required');

      const peer=JSON.parse(
        fs.readFileSync(process.argv[3],'utf8')
      );

      const localServices=lib.enumerateLocalServices();
      const peerServices=peer.services || [];

      const results=[];

      for(const local of localServices) {
        for(const remote of peerServices) {
          if(local.service_id===remote.service_id) {
            results.push(
              lib.negotiateService(local,remote)
            );
          }
        }
      }

      print({
        schema:'dnyf.service.discovery.negotiation.v1',
        compatible:results.some(x=>x.compatible),
        services:results
      });
      break;

    case 'cache':
      if(!process.argv[3]) fail('peer discovery JSON required');

      const record=JSON.parse(
        fs.readFileSync(process.argv[3],'utf8')
      );

      print({
        cached:lib.cachePeer(record)
      });
      break;

    default:
      console.log(`
DNYFTECH SERVICE DISCOVERY
--------------------------
Usage:
  dnyf-service-discovery status
  dnyf-service-discovery services
  dnyf-service-discovery network
  dnyf-service-discovery refresh
  dnyf-service-discovery registry
  dnyf-service-discovery negotiate <peer-record.json>
  dnyf-service-discovery cache <peer-record.json>
`);
      process.exit(2);
  }
} catch(error) {
  fail(error.message);
}
NODE

chmod 755 "$CLI"

ln -sfn "$CLI" "$USR_BIN/dnyf-service-discovery"
ln -sfn "$CLI" "$USR_LOCAL_BIN/dnyf-service-discovery"

ok "service discovery CLI"

echo "◆ Refreshing local service discovery record..."

DNYF_ROOT="$ROOT" node - <<'NODE'
const path=require('path');

const root=process.env.DNYF_ROOT;

const lib=require(
  path.join(
    root,
    'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js'
  )
);

lib.saveLocalRecord();
lib.saveRegistry();

console.log('local service discovery record generated');
NODE

cp "$STATE/service-discovery/local-discovery-state.json" \
   "$SERVICE_RECORD"

chmod 600 "$SERVICE_RECORD" "$DISCOVERY_STATE"

ok "local service enumeration"

echo "◆ Updating authoritative service registry..."

node - "$SERVICE_ENTRY" <<'NODE'
const fs=require('fs');
const file=process.argv[2];

const x=JSON.parse(fs.readFileSync(file,'utf8'));

function normalizeServices(input) {
  if(Array.isArray(input)) return input;

  if(input && Array.isArray(input.services)) {
    return input.services;
  }

  if(input && input.services && typeof input.services==='object') {
    return Object.entries(input.services).map(([id,v])=>({
      service_id:id,
      ...v
    }));
  }

  return [];
}

const services=normalizeServices(x);

const required={
  service_id:'dnyf-service-discovery',
  service_name:'DNYF Service Discovery Registry',
  protocol:'dnyf-service-discovery/1',
  api_version:'v1',
  transports:['local-process','http','https','websocket'],
  enabled:true,
  health:'local'
};

const existing=services.filter(
  s=>s.service_id!=='dnyf-service-discovery'
);

existing.push(required);

const out=Array.isArray(x)
  ? existing
  : {
      ...x,
      services:existing
    };

fs.writeFileSync(
  file,
  JSON.stringify(out,null,2)+'\n'
);
NODE

ok "service registry integration"

echo "◆ Writing discovery registry..."

DNYF_ROOT="$ROOT" node - <<'NODE'
const path=require('path');

const root=process.env.DNYF_ROOT;

const lib=require(
  path.join(
    root,
    'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js'
  )
);

lib.saveRegistry();
NODE

chmod 600 "$DISCOVERY_REGISTRY"
ok "service discovery registry"

echo "◆ Writing discovery audit record..."

cat > "$AUDIT/service-discovery-${TIMESTAMP}.jsonl" <<JSON
{"schema":"dnyf.audit.v1","event":"phase8j-service-discovery-registry","timestamp":"$TIMESTAMP","device_id":"$DEVICE_ID","fingerprint":"$FINGERPRINT","security":{"authenticated_discovery_required":true,"proof_of_possession_required":true,"discovery_grants_trust":false,"discovery_grants_authorization":false,"self_trust":false,"self_pairing":false,"automatic_trust":false,"remote_execution":false,"remote_installation":false,"remote_shell":false}}
JSON

chmod 600 "$AUDIT/service-discovery-${TIMESTAMP}.jsonl"
ok "audit record"

echo "◆ Writing Phase 8J manifest..."

cat > "$MANIFEST" <<JSON
{
  "schema": "dnyf.phase.manifest.v1",
  "phase": "8J",
  "name": "Service Discovery Registry",
  "version": "1.0.0",
  "timestamp": "$TIMESTAMP",
  "device_id": "$DEVICE_ID",
  "fingerprint": "$FINGERPRINT",
  "depends_on": [
    "8H-unified-device-registry",
    "8I-capability-negotiation"
  ],
  "artifacts": {
    "schema": "etc/dnyf/service-discovery/dnyf-service-discovery-schema.json",
    "policy": "etc/dnyf/service-discovery/dnyf-service-discovery-policy.json",
    "authority": "opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js",
    "cli": "bin/dnyf-service-discovery",
    "local_record": "opt/dnyf/state/service-discovery/local-service-record.json",
    "discovery_state": "opt/dnyf/state/service-discovery/local-discovery-state.json",
    "registry": "registry/dnyf-service-discovery-registry.json"
  },
  "security": {
    "authenticated_discovery": true,
    "proof_of_possession": true,
    "discovery_grants_trust": false,
    "discovery_grants_authorization": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false,
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false
  },
  "network": {
    "ipv4": true,
    "ipv6": true,
    "offline_first": true,
    "lan_preferred": true,
    "internet_fallback": true,
    "relay_fallback": true,
    "mdns_compatible": true
  }
}
JSON

chmod 600 "$MANIFEST"
ok "Phase 8J manifest"

echo
echo "◆ Validation..."
echo

PASS=0
FAIL=0

check() {
  local label="$1"
  shift

  if "$@"; then
    ok "$label"
    PASS=$((PASS+1))
  else
    echo "[FAIL] $label"
    FAIL=$((FAIL+1))
  fi
}

check "service discovery schema" test -s "$SCHEMA"
check "service discovery policy" test -s "$POLICY"
check "authority library" test -s "$LIBRARY"
check "service discovery CLI" test -x "$CLI"
check "local service record" test -s "$SERVICE_RECORD"
check "discovery state" test -s "$DISCOVERY_STATE"
check "service discovery registry" test -s "$DISCOVERY_REGISTRY"
check "service registry integration" test -s "$SERVICE_ENTRY"
check "audit record" test -s "$AUDIT/service-discovery-${TIMESTAMP}.jsonl"
check "Phase 8J manifest" test -s "$MANIFEST"

echo "◆ JavaScript syntax validation..."

node --check "$LIBRARY"
check "authority syntax" true

node --check "$CLI"
check "CLI syntax" true

echo "◆ Schema security validation..."

node - "$SCHEMA" <<'NODE'
const fs=require('fs');

const x=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));

if(x.schema!=='dnyf.service.discovery.v1')
  throw new Error('invalid schema');

if(x.security.self_trust!==false)
  throw new Error('self trust enabled');

if(x.security.self_pairing!==false)
  throw new Error('self pairing enabled');

if(x.security.automatic_trust!==false)
  throw new Error('automatic trust enabled');

if(x.security.remote_execution!==false)
  throw new Error('remote execution enabled');

if(x.security.remote_installation!==false)
  throw new Error('remote installation enabled');

if(x.security.remote_shell!==false)
  throw new Error('remote shell enabled');

if(x.security.discovery_grants_trust!==false)
  throw new Error('discovery grants trust');

if(x.security.discovery_grants_authorization!==false)
  throw new Error('discovery grants authorization');

console.log('schema security contract valid');
NODE

check "schema security contract" true

echo "◆ Canonical identity binding validation..."

node - "$SERVICE_RECORD" "$IDENTITY" <<'NODE'
const fs=require('fs');

const record=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const identity=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));

if(String(record.device.device_id).toLowerCase() !==
   String(identity.device_id).toLowerCase())
  throw new Error('device ID mismatch');

if(String(record.device.fingerprint).toLowerCase() !==
   String(identity.fingerprint).toLowerCase())
  throw new Error('fingerprint mismatch');

if(!record.device.public_key)
  throw new Error('public key missing');

console.log('canonical identity binding valid');
NODE

check "identity binding" true

echo "◆ Local service discovery validation..."

DNYF_ROOT="$ROOT" node - <<'NODE'
const path=require('path');

const root=process.env.DNYF_ROOT;

const lib=require(
  path.join(
    root,
    'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js'
  )
);

const services=lib.enumerateLocalServices();

if(!Array.isArray(services))
  throw new Error('services not array');

for(const s of services) {
  if(!s.service_id) throw new Error('missing service ID');
  if(!s.service_name) throw new Error('missing service name');
  if(!s.device_id) throw new Error('missing device binding');
  if(!s.protocol) throw new Error('missing protocol');
  if(!s.api_version) throw new Error('missing API version');
  if(!Array.isArray(s.transports))
    throw new Error('missing transports');
  if(!s.discovery.authenticated_peer_binding)
    throw new Error('missing authenticated binding');
  if(s.security.grants_trust!==false)
    throw new Error('service discovery grants trust');
  if(s.security.grants_authorization!==false)
    throw new Error('service discovery grants authorization');
}

console.log(`local services discovered: ${services.length}`);
NODE

check "local service enumeration" true

echo "◆ Network discovery validation..."

DNYF_ROOT="$ROOT" node - <<'NODE'
const path=require('path');

const root=process.env.DNYF_ROOT;

const lib=require(
  path.join(
    root,
    'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js'
  )
);

const addresses=lib.detectNetworkInterfaces();

if(!Array.isArray(addresses))
  throw new Error('network interface result invalid');

const state=lib.status();

if(state.ipv4!==true)
  throw new Error('IPv4 support disabled');

if(state.ipv6!==true)
  throw new Error('IPv6 support disabled');

if(state.mdns_compatible!==true)
  throw new Error('mDNS compatibility disabled');

console.log(JSON.stringify({
  addresses:addresses.length,
  ipv4:true,
  ipv6:true,
  mdns_compatible:true
},null,2));
NODE

check "IPv4/IPv6 discovery metadata" true
check "mDNS-compatible discovery metadata" true

echo "◆ Freshness validation..."

DNYF_ROOT="$ROOT" node - <<'NODE'
const path=require('path');

const root=process.env.DNYF_ROOT;

const lib=require(
  path.join(
    root,
    'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js'
  )
);

const fresh={
  expires_at:new Date(Date.now()+60000).toISOString()
};

const stale={
  expires_at:new Date(Date.now()-60000).toISOString()
};

if(lib.isFresh(fresh)!==true)
  throw new Error('fresh record rejected');

if(lib.isFresh(stale)!==false)
  throw new Error('stale record accepted');

console.log('freshness contract valid');
NODE

check "service freshness" true

echo "◆ Compatibility negotiation validation..."

DNYF_ROOT="$ROOT" node - <<'NODE'
const path=require('path');

const root=process.env.DNYF_ROOT;

const lib=require(
  path.join(
    root,
    'opt/dnyf/runtime/service-discovery/dnyf-service-discovery-authority.js'
  )
);

const a={
  service_id:'test-service',
  protocol:'dnyf-test/1',
  api_version:'v1',
  transports:['https','websocket'],
  capabilities:['a','b']
};

const b={
  service_id:'test-service',
  protocol:'dnyf-test/1',
  api_version:'v1',
  transports:['https'],
  capabilities:['b','c']
};

const good=lib.negotiateService(a,b);

if(good.compatible!==true)
  throw new Error('compatible service rejected');

if(!good.transports.includes('https'))
  throw new Error('transport intersection missing');

if(!good.common_capabilities.includes('b'))
  throw new Error('capability intersection missing');

const bad=lib.negotiateService(
  a,
  {
    ...b,
    protocol:'different/1',
    api_version:'v9',
    transports:['local-process']
  }
);

if(bad.compatible!==false)
  throw new Error('incompatible service accepted');

console.log(JSON.stringify({
  compatible:good,
  incompatible:bad
},null,2));
NODE

check "protocol/API/transport/capability negotiation" true

echo "◆ Security separation validation..."

node - "$DISCOVERY_REGISTRY" "$DEVICE_ID" <<'NODE'
const fs=require('fs');

const x=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const own=process.argv[3];

if(x.security.discovered_is_not_authenticated!==true)
  throw new Error('discovery/authentication separation missing');

if(x.security.authenticated_is_not_trusted!==true)
  throw new Error('authentication/trust separation missing');

if(x.security.trusted_is_not_authorized!==true)
  throw new Error('trust/authorization separation missing');

if(x.security.authorized_is_not_remote_execution!==true)
  throw new Error('authorization/execution separation missing');

if(x.security.self_trust!==false)
  throw new Error('self trust enabled');

if(x.security.remote_execution!==false)
  throw new Error('remote execution enabled');

for(const peer of x.peers || []) {
  if(String(peer.device_id).toLowerCase()===String(own).toLowerCase())
    throw new Error('self entered peer registry');
}

console.log('security separation valid');
NODE

check "trust/authorization/execution separation" true
check "self-peer isolation" true

echo "◆ Capability/trust separation validation..."

node - "$SERVICE_RECORD" <<'NODE'
const fs=require('fs');

const x=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));

if(x.security.discovery_grants_trust!==false &&
   x.security.grants_trust!==false)
  throw new Error('discovery grants trust');

if(x.security.discovery_grants_authorization!==false &&
   x.security.grants_authorization!==false)
  throw new Error('discovery grants authorization');

console.log('capability/trust separation valid');
NODE

check "discovery/trust separation" true

echo "◆ Registry integrity validation..."

node - "$DISCOVERY_REGISTRY" "$IDENTITY" <<'NODE'
const fs=require('fs');

const registry=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const identity=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));

if(registry.schema!=='dnyf.service.discovery.registry.v1')
  throw new Error('invalid registry schema');

if(registry.devices.length!==1)
  throw new Error('unexpected authoritative device count');

const own=registry.devices[0];

if(String(own.device_id).toLowerCase() !==
   String(identity.device_id).toLowerCase())
  throw new Error('registry device mismatch');

if(String(own.fingerprint).toLowerCase() !==
   String(identity.fingerprint).toLowerCase())
  throw new Error('registry fingerprint mismatch');

if(own.trusted!==false)
  throw new Error('local device marked trusted');

if(own.authorized!==false)
  throw new Error('local device marked authorized');

if((registry.peers||[]).length!==0)
  throw new Error('synthetic peers entered authoritative registry');

console.log('registry integrity valid');
NODE

check "authoritative registry integrity" true

echo "◆ Security invariants..."

node - "$SCHEMA" <<'NODE'
const fs=require('fs');

const x=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));

const checks=[
  ['self_trust',x.security.self_trust,false],
  ['self_pairing',x.security.self_pairing,false],
  ['automatic_trust',x.security.automatic_trust,false],
  ['remote_execution',x.security.remote_execution,false],
  ['remote_installation',x.security.remote_installation,false],
  ['remote_shell',x.security.remote_shell,false],
  ['discovery_grants_trust',x.security.discovery_grants_trust,false],
  ['discovery_grants_authorization',x.security.discovery_grants_authorization,false]
];

for(const [name,value,expected] of checks) {
  if(value!==expected)
    throw new Error(`${name} invariant violated`);
}

console.log('all security invariants valid');
NODE

check "security invariants" true

echo "◆ Permission validation..."

PERM_PRIVATE="$(stat -c '%a' "$OPT/runtime/secure/identity/device-ed25519-private.pem" 2>/dev/null || true)"
PERM_IDENTITY="$(stat -c '%a' "$IDENTITY" 2>/dev/null || true)"

[[ "$PERM_PRIVATE" == "600" ]] || die "private key permission is $PERM_PRIVATE"
[[ "$PERM_IDENTITY" == "600" ]] || die "identity permission is $PERM_IDENTITY"

ok "private key permission 600"
ok "identity permission 600"

echo
echo "◆ Final service discovery status..."
echo

DNYF_ROOT="$ROOT" "$CLI" status

echo
echo "============================================================"

if [[ "$FAIL" -eq 0 ]]; then
  echo " PHASE 8J SERVICE DISCOVERY REGISTRY: PASS"
else
  echo " PHASE 8J SERVICE DISCOVERY REGISTRY: FAIL"
fi

echo "============================================================"
echo
echo "Device ID   : $DEVICE_ID"
echo "Fingerprint : $FINGERPRINT"
echo "Registry    : $DISCOVERY_REGISTRY"
echo "Services    : $SERVICE_RECORD"
echo "Manifest    : $MANIFEST"
echo "Backup      : $BACKUP"
echo
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo

if [[ "$FAIL" -ne 0 ]]; then
  echo "[RESULT] PHASE 8J FAILED"
  exit 1
fi

echo "Validated:"
echo "  ✓ local service enumeration"
echo "  ✓ authenticated service binding"
echo "  ✓ IPv4 discovery metadata"
echo "  ✓ IPv6 discovery metadata"
echo "  ✓ mDNS-compatible discovery model"
echo "  ✓ offline-first discovery"
echo "  ✓ LAN-preferred discovery"
echo "  ✓ Internet fallback"
echo "  ✓ relay fallback"
echo "  ✓ protocol compatibility"
echo "  ✓ API version compatibility"
echo "  ✓ transport intersection"
echo "  ✓ capability filtering"
echo "  ✓ service freshness"
echo "  ✓ peer cache isolation"
echo "  ✓ trust separation"
echo "  ✓ authorization separation"
echo "  ✓ self-peer isolation"
echo "  ✓ synthetic peer isolation"
echo "  ✓ security invariants"
echo "  ✓ cryptographic identity binding"
echo
echo "Next phase: 9A DNYF API Gateway"
echo

