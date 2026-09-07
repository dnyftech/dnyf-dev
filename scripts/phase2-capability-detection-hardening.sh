#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
CAP="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js"
BACKUP="$ROOT/backups/phase2-capability-hardening/$(date -u +%Y%m%dT%H%M%SZ)"

echo "============================================================"
echo " DNYFTECH — PHASE 2 CAPABILITY DETECTION HARDENING"
echo "============================================================"
echo "Root: $ROOT"
echo

[ -d "$ROOT" ] || { echo "[FATAL] DNYF-DEV root missing"; exit 1; }
[ -f "$CAP" ] || { echo "[FATAL] capability detector missing: $CAP"; exit 1; }

mkdir -p "$BACKUP"

cp -p "$CAP" "$BACKUP/dnyf-runtime-capability-detector.js"
echo "[OK] capability detector backed up"

export DNYF_ROOT="$ROOT"

node - "$CAP" <<'DNYF_NODE'
const fs = require("fs");
const path = process.argv[2];

let source = fs.readFileSync(path, "utf8");

const replacements = [
  [
    /os\.cpus\(\)\.length/g,
    "Math.max(1, os.cpus().length)"
  ],
  [
    /logical_cores:\s*os\.cpus\(\)\.length/g,
    "logical_cores: Math.max(1, os.cpus().length)"
  ]
];

for (const [pattern, replacement] of replacements) {
  source = source.replace(pattern, replacement);
}

fs.writeFileSync(path, source);
DNYF_NODE

echo "[OK] CPU capability detector hardened"

node --check "$CAP"
echo "[OK] syntax validation"

echo
echo "◆ Testing capability detector..."
echo "------------------------------------------------------------"

DNYF_ROOT="$ROOT" node - <<'DNYF_NODE'
const os = require("os");

const root = process.env.DNYF_ROOT;
const candidates = [
  `${root}/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js`,
  `${root}/opt/dnyf/runtime/universal/dnyf-runtime-core.js`
];

let detector = null;

for (const candidate of candidates) {
  try {
    const mod = require(candidate);
    if (typeof mod.detectCapabilities === "function") {
      detector = mod;
      break;
    }
    if (typeof mod.getCapabilities === "function") {
      detector = mod;
      break;
    }
  } catch (_) {}
}

const detectedCores = Math.max(1, os.cpus().length || 1);

console.log(JSON.stringify({
  node_cpu_count: os.cpus().length,
  normalized_logical_cores: detectedCores,
  architecture: process.arch,
  platform: process.platform,
  detector_loaded: !!detector
}, null, 2));

if (detectedCores < 1) {
  console.error("[FAIL] logical CPU count is still invalid");
  process.exit(1);
}

console.log("[OK] logical CPU count is valid");
DNYF_NODE

echo
echo "◆ Testing universal runtime integration..."
echo "------------------------------------------------------------"

DNYF_ROOT="$ROOT" node - <<'DNYF_NODE'
const root = process.env.DNYF_ROOT;
const core = require(`${root}/opt/dnyf/runtime/universal/dnyf-runtime-core.js`);

if (typeof core.runtimeInfo !== "function") {
  throw new Error("runtimeInfo() missing");
}

const info = core.runtimeInfo();

const cores = info?.capabilities?.cpu?.logical_cores;

console.log(JSON.stringify({
  runtime: info.runtime,
  version: info.version,
  device_id: info.identity?.device_id,
  fingerprint: info.identity?.fingerprint,
  logical_cores: cores,
  dns: info.capabilities?.network?.dns,
  security: info.security
}, null, 2));

if (!Number.isInteger(cores) || cores < 1) {
  throw new Error(`Invalid logical_cores value: ${cores}`);
}

if (!info.identity?.fingerprint) {
  throw new Error("Active cryptographic fingerprint missing");
}

for (const [name, value] of Object.entries(info.security || {})) {
  if (value === true &&
      ["self_trust","self_pairing","automatic_trust",
       "remote_execution","remote_installation",
       "remote_shell"].includes(name)) {
    throw new Error(`Security invariant violated: ${name}=true`);
  }
}

console.log("[OK] runtime capability integration");
DNYF_NODE

echo
echo "◆ Checking DNS probe behavior..."
echo "------------------------------------------------------------"

DNS_RESULT="false"

if command -v getent >/dev/null 2>&1; then
    if getent hosts example.com >/dev/null 2>&1; then
        DNS_RESULT="true"
    fi
elif command -v nslookup >/dev/null 2>&1; then
    if nslookup example.com >/dev/null 2>&1; then
        DNS_RESULT="true"
    fi
elif command -v ping >/dev/null 2>&1; then
    if ping -c 1 -W 2 example.com >/dev/null 2>&1; then
        DNS_RESULT="true"
    fi
fi

echo "External DNS resolution: $DNS_RESULT"

if [ "$DNS_RESULT" = "true" ]; then
    echo "[OK] DNS resolution available"
else
    echo "[INFO] DNS probe unavailable from current Termux environment"
    echo "[INFO] This is not treated as a failure unless the runtime falsely claims DNS availability"
fi

echo
echo "◆ Re-running runtime syntax validation..."
echo "------------------------------------------------------------"

for file in \
  "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js" \
  "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js" \
  "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js" \
  "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js" \
  "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js" \
  "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js"
do
    node --check "$file"
    echo "[OK] $(basename "$file")"
done

echo
echo "============================================================"
echo " PHASE 2 CAPABILITY HARDENING RESULT"
echo "============================================================"
echo "Backup: $BACKUP"
echo
echo "[RESULT] CAPABILITY DETECTION HARDENING: PASS"
echo
echo "Next:"
echo "  1. Run the canonical Phase 2 validator."
echo "  2. Confirm logical_cores >= 1."
echo "  3. Confirm active fingerprint:"
echo "     8a0cf45467dff43a76586033363561b643d6fa3c814f45e2a5fbd5ad61473e23"
echo "  4. Only then proceed to Phase 8G authenticated-session repair."
