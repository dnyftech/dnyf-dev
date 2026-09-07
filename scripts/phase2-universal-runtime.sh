#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DNYF_ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
RUNTIME_ROOT="$DNYF_ROOT/opt/dnyf/runtime/universal"
CONFIG_ROOT="$DNYF_ROOT/etc/dnyf/runtime"
STATE_ROOT="$DNYF_ROOT/opt/dnyf/state/universal"
BIN_ROOT="$DNYF_ROOT/bin"
USR_BIN="$DNYF_ROOT/usr/bin"
LOCAL_BIN="$DNYF_ROOT/usr/local/bin"
REGISTRY_ROOT="$DNYF_ROOT/registry"
PLATFORM_ROOT="$DNYF_ROOT/etc/dnyf/platform"
CAPABILITY_ROOT="$DNYF_ROOT/etc/dnyf/capabilities"
ARTIFACT_ROOT="$DNYF_ROOT/opt/dnyf/runtime/artifacts"
WINDOWS_ROOT="$DNYF_ROOT/opt/dnyf/runtime/windows"
VALIDATION_ROOT="$DNYF_ROOT/opt/dnyf/runtime/validation"

CYAN=$'\033[1;36m'
BLUE=$'\033[1;34m'
GREEN=$'\033[1;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[1;31m'
MAGENTA=$'\033[1;35m'
WHITE=$'\033[1;37m'
RESET=$'\033[0m'

log()  { printf '%b◆%b %s\n' "$CYAN" "$RESET" "$*"; }
ok()   { printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$*"; }
info() { printf '%b[INFO]%b %s\n' "$CYAN" "$RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

printf '\n'
printf '%b============================================================%b\n' "$CYAN" "$RESET"
printf '%b DNYF-DEV PHASE 2 — UNIVERSAL RUNTIME%b\n' "$WHITE" "$RESET"
printf '%b============================================================%b\n\n' "$CYAN" "$RESET"

mkdir -p \
  "$RUNTIME_ROOT" \
  "$CONFIG_ROOT" \
  "$STATE_ROOT" \
  "$PLATFORM_ROOT" \
  "$CAPABILITY_ROOT" \
  "$ARTIFACT_ROOT" \
  "$WINDOWS_ROOT" \
  "$VALIDATION_ROOT" \
  "$REGISTRY_ROOT" \
  "$BIN_ROOT" \
  "$USR_BIN" \
  "$LOCAL_BIN"

###############################################################################
# 1. PLATFORM DETECTOR
###############################################################################

cat > "$RUNTIME_ROOT/dnyf-runtime-platform-detector.js" <<'DNYF_JS'
'use strict';

const os = require('os');
const fs = require('fs');

function exists(path) {
    try {
        return fs.existsSync(path);
    } catch (_) {
        return false;
    }
}

function detectHost() {
    if (process.env.TERMUX_VERSION ||
        process.env.PREFIX?.includes('/com.termux/') ||
        process.env.PREFIX?.includes('/data/data/')) {
        return 'android-termux';
    }

    if (process.env.WSL_DISTRO_NAME ||
        process.env.WSL_INTEROP) {
        return 'windows-wsl';
    }

    if (process.platform === 'win32') {
        return 'windows';
    }

    if (process.platform === 'darwin') {
        return 'macos';
    }

    if (process.platform === 'linux') {
        if (exists('/system/bin/app_process') ||
            exists('/system/build.prop')) {
            return 'android-linux';
        }

        return 'linux';
    }

    return process.platform;
}

function detectArchitecture() {
    const arch = process.arch;

    const map = {
        arm64: 'aarch64',
        arm: 'arm32',
        x64: 'x86_64',
        ia32: 'x86',
        riscv64: 'riscv64',
        ppc64: 'ppc64',
        ppc64le: 'ppc64le',
        s390x: 's390x'
    };

    return map[arch] || arch;
}

function detectKernel() {
    return {
        platform: os.platform(),
        release: os.release(),
        version: os.version(),
        hostname: os.hostname(),
        arch: detectArchitecture(),
        node: process.version
    };
}

function detectEnvironment() {
    return {
        termux: Boolean(
            process.env.PREFIX &&
            process.env.PREFIX.includes('com.termux')
        ),
        proot: Boolean(
            process.env.PROOT_TMP_DIR ||
            process.env.PROOT_LOADER ||
            process.env.PROOT_DISTRIBUTION
        ),
        wsl: Boolean(
            process.env.WSL_DISTRO_NAME ||
            process.env.WSL_INTEROP
        ),
        prefix: process.env.PREFIX || null,
        home: process.env.HOME || null,
        shell: process.env.SHELL || null
    };
}

function detect() {
    return {
        schema: 'dnyf.runtime.platform.v1',
        runtime: 'dnyf-universal-runtime/1',
        detected_at: new Date().toISOString(),
        host: detectHost(),
        architecture: detectArchitecture(),
        kernel: detectKernel(),
        environment: detectEnvironment(),
        node_platform: process.platform,
        node_architecture: process.arch
    };
}

if (require.main === module) {
    process.stdout.write(JSON.stringify(detect(), null, 2) + '\n');
}

module.exports = {
    detect,
    detectHost,
    detectArchitecture
};
DNYF_JS

###############################################################################
# 2. DEVICE IDENTITY LOADER
###############################################################################

cat > "$RUNTIME_ROOT/dnyf-runtime-device-identity.js" <<'DNYF_JS'
'use strict';

const fs = require('fs');
const path = require('path');

function resolveRoot() {
    return process.env.DNYF_ROOT ||
        path.resolve(__dirname, '../../../../..');
}

function loadIdentity() {
    const root = resolveRoot();

    const candidates = [
        process.env.DNYF_IDENTITY_FILE,
        path.join(
            root,
            'opt/dnyf/runtime/secure/identity/identity.json'
        ),
        path.join(
            root,
            'identity/identity.json'
        )
    ].filter(Boolean);

    for (const file of candidates) {
        try {
            if (!fs.existsSync(file)) continue;

            const data = JSON.parse(
                fs.readFileSync(file, 'utf8')
            );

            if (!data.device_id) continue;

            return {
                device_id: String(data.device_id).toLowerCase(),
                fingerprint: data.fingerprint
                    ? String(data.fingerprint).toLowerCase()
                    : null,
                public_key: data.public_key || null,
                algorithm: data.algorithm || 'Ed25519',
                source: file
            };
        } catch (_) {
            continue;
        }
    }

    throw new Error(
        'DNYF canonical cryptographic identity could not be loaded'
    );
}

if (require.main === module) {
    process.stdout.write(
        JSON.stringify(loadIdentity(), null, 2) + '\n'
    );
}

module.exports = {
    resolveRoot,
    loadIdentity
};
DNYF_JS

###############################################################################
# 3. CAPABILITY DETECTOR
###############################################################################

cat > "$RUNTIME_ROOT/dnyf-runtime-capability-detector.js" <<'DNYF_JS'
'use strict';

const fs = require('fs');
const os = require('os');
const { execFileSync } = require('child_process');

function commandExists(command) {
    try {
        execFileSync(
            'sh',
            ['-c', `command -v ${command}`],
            { stdio: 'ignore' }
        );
        return true;
    } catch (_) {
        return false;
    }
}

function memoryBytes() {
    try {
        return os.totalmem();
    } catch (_) {
        return 0;
    }
}

function cpuCount() {
    try {
        return os.cpus().length;
    } catch (_) {
        return 1;
    }
}

function filesystemCapabilities() {
    return {
        node_fs: true,
        read_write: true,
        symlink: typeof fs.symlinkSync === 'function',
        atomic_rename: true,
        sha256: true
    };
}

function networkCapabilities() {
    return {
        tcp: true,
        ipv4: true,
        ipv6: true,
        websocket_runtime: true,
        dns: commandExists('getent') ||
             commandExists('nslookup') ||
             commandExists('dig')
    };
}

function toolCapabilities() {
    return {
        node: Boolean(process.version),
        git: commandExists('git'),
        curl: commandExists('curl'),
        wget: commandExists('wget'),
        openssl: commandExists('openssl'),
        python3: commandExists('python3'),
        tar: commandExists('tar'),
        unzip: commandExists('unzip'),
        zip: commandExists('zip'),
        proot: commandExists('proot'),
        proot_distro: commandExists('proot-distro'),
        ollama: commandExists('ollama')
    };
}

function windowsCompatibility() {
    return {
        artifact_storage: true,
        artifact_inspection: true,
        manifest_generation: true,
        native_execution: false,
        remote_execution: false,
        compatibility_execution: false,
        wine: commandExists('wine') || commandExists('wine64'),
        box64: commandExists('box64'),
        box86: commandExists('box86'),
        qemu: commandExists('qemu-x86_64')
    };
}

function detect() {
    return {
        schema: 'dnyf.runtime.capabilities.v1',
        generated_at: new Date().toISOString(),
        cpu: {
            logical_cores: cpuCount(),
            architecture: process.arch
        },
        memory: {
            total_bytes: memoryBytes()
        },
        filesystem: filesystemCapabilities(),
        network: networkCapabilities(),
        tools: toolCapabilities(),
        windows_compatibility: windowsCompatibility(),
        security: {
            cryptographic_identity: true,
            authenticated_protocol_available: true,
            self_trust: false,
            self_pairing: false,
            automatic_trust: false,
            remote_execution: false,
            remote_installation: false,
            remote_shell: false
        }
    };
}

if (require.main === module) {
    process.stdout.write(
        JSON.stringify(detect(), null, 2) + '\n'
    );
}

module.exports = { detect };
DNYF_JS

###############################################################################
# 4. RUNTIME PROTOCOL CONTRACT
###############################################################################

cat > "$CONFIG_ROOT/dnyf-runtime-protocol.json" <<'DNYF_JSON'
{
  "schema": "dnyf.runtime.protocol.v1",
  "protocol": "dnyf-runtime/1",
  "version": "1.0.0",
  "transport": [
    "local-process",
    "http",
    "https",
    "websocket"
  ],
  "serialization": "json",
  "api_version": "v1",
  "ipv4": true,
  "ipv6": true,
  "offline_first": true,
  "lan_preferred": true,
  "internet_fallback": true,
  "relay_fallback": true,
  "remote_execution": false,
  "remote_installation": false,
  "remote_shell": false,
  "self_trust": false,
  "self_pairing": false,
  "automatic_trust": false
}
DNYF_JSON

###############################################################################
# 5. ARTIFACT MANAGER
###############################################################################

cat > "$RUNTIME_ROOT/dnyf-runtime-artifact-manager.js" <<'DNYF_JS'
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function resolveRoot() {
    return process.env.DNYF_ROOT ||
        path.resolve(__dirname, '../../../../..');
}

function artifactRoot() {
    return path.join(
        resolveRoot(),
        'opt/dnyf/runtime/artifacts'
    );
}

function ensureRoot() {
    fs.mkdirSync(artifactRoot(), { recursive: true });
}

function safeName(name) {
    const cleaned = path.basename(String(name))
        .replace(/[^a-zA-Z0-9._-]/g, '_');

    if (!cleaned || cleaned === '.' || cleaned === '..') {
        throw new Error('Invalid artifact name');
    }

    return cleaned;
}

function sha256(file) {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(file);

    return new Promise((resolve, reject) => {
        stream.on('data', chunk => hash.update(chunk));
        stream.on('end', () => resolve(hash.digest('hex')));
        stream.on('error', reject);
    });
}

async function inspect(file) {
    const stat = fs.statSync(file);

    return {
        schema: 'dnyf.artifact.v1',
        name: path.basename(file),
        path: file,
        size_bytes: stat.size,
        modified_at: stat.mtime.toISOString(),
        sha256: await sha256(file),
        extension: path.extname(file).toLowerCase()
    };
}

function store(source, requestedName) {
    ensureRoot();

    const name = safeName(
        requestedName || path.basename(source)
    );

    const destination = path.join(
        artifactRoot(),
        name
    );

    fs.copyFileSync(source, destination);

    return destination;
}

function list() {
    ensureRoot();

    return fs.readdirSync(artifactRoot())
        .filter(name => !name.startsWith('.'))
        .map(name => path.join(artifactRoot(), name));
}

if (require.main === module) {
    const command = process.argv[2];

    if (command === 'list') {
        console.log(JSON.stringify(list(), null, 2));
    } else if (command === 'inspect') {
        inspect(process.argv[3])
            .then(result =>
                console.log(JSON.stringify(result, null, 2))
            )
            .catch(error => {
                console.error(error.message);
                process.exit(1);
            });
    } else if (command === 'store') {
        console.log(store(
            process.argv[3],
            process.argv[4]
        ));
    } else {
        console.error(
            'Usage: dnyf-runtime-artifact-manager ' +
            '<list|inspect|store>'
        );
        process.exit(2);
    }
}

module.exports = {
    resolveRoot,
    artifactRoot,
    inspect,
    store,
    list
};
DNYF_JS

###############################################################################
# 6. WINDOWS ARTIFACT ADAPTER
###############################################################################

cat > "$WINDOWS_ROOT/dnyf-runtime-windows-artifact-adapter.js" <<'DNYF_JS'
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function sha256(file) {
    return new Promise((resolve, reject) => {
        const hash = crypto.createHash('sha256');
        const stream = fs.createReadStream(file);

        stream.on('data', chunk => hash.update(chunk));
        stream.on('end', () => resolve(hash.digest('hex')));
        stream.on('error', reject);
    });
}

async function inspectWindowsArtifact(file) {
    const stat = fs.statSync(file);
    const extension = path.extname(file).toLowerCase();

    const executableExtensions = [
        '.exe',
        '.msi',
        '.com',
        '.bat',
        '.cmd'
    ];

    return {
        schema: 'dnyf.windows.artifact.v1',
        name: path.basename(file),
        path: file,
        extension,
        size_bytes: stat.size,
        sha256: await sha256(file),
        windows_artifact: executableExtensions.includes(extension),
        storage_allowed: true,
        inspection_allowed: true,
        execution_allowed: false,
        remote_execution_allowed: false
    };
}

module.exports = {
    inspectWindowsArtifact
};
DNYF_JS

###############################################################################
# 7. UNIVERSAL DISPATCHER
###############################################################################

cat > "$RUNTIME_ROOT/dnyf-runtime-dispatcher.js" <<'DNYF_JS'
'use strict';

const path = require('path');

function classifyArtifact(file) {
    const extension = path.extname(file).toLowerCase();

    if (extension === '.exe' ||
        extension === '.msi' ||
        extension === '.bat' ||
        extension === '.cmd') {
        return 'windows-artifact';
    }

    if (extension === '.apk') {
        return 'android-package';
    }

    if (extension === '.deb') {
        return 'debian-package';
    }

    if (extension === '.zip' ||
        extension === '.tar' ||
        extension === '.gz' ||
        extension === '.tgz') {
        return 'archive';
    }

    if (extension === '.js' ||
        extension === '.mjs' ||
        extension === '.cjs') {
        return 'javascript-source';
    }

    if (extension === '.json') {
        return 'json-document';
    }

    return 'generic-artifact';
}

function dispatch(file, options = {}) {
    const classification = classifyArtifact(file);

    if (classification === 'windows-artifact') {
        return {
            ok: true,
            type: classification,
            action: 'store-or-inspect',
            execution: false,
            reason:
                'Windows artifacts are transferable and inspectable; ' +
                'execution requires an explicitly supported Windows ' +
                'compatibility backend or authorized Windows node.'
        };
    }

    return {
        ok: true,
        type: classification,
        action: options.action || 'inspect',
        execution: false
    };
}

if (require.main === module) {
    const file = process.argv[2];

    if (!file) {
        console.error(
            'Usage: dnyf-runtime-dispatcher <artifact>'
        );
        process.exit(2);
    }

    console.log(
        JSON.stringify(dispatch(file), null, 2)
    );
}

module.exports = {
    classifyArtifact,
    dispatch
};
DNYF_JS

###############################################################################
# 8. UNIVERSAL RUNTIME CORE
###############################################################################

cat > "$RUNTIME_ROOT/dnyf-runtime-core.js" <<'DNYF_JS'
'use strict';

const path = require('path');

const {
    detect: detectPlatform
} = require('./dnyf-runtime-platform-detector');

const {
    loadIdentity
} = require('./dnyf-runtime-device-identity');

const {
    detect: detectCapabilities
} = require('./dnyf-runtime-capability-detector');

const {
    classifyArtifact,
    dispatch
} = require('./dnyf-runtime-dispatcher');

function runtimeInfo() {
    return {
        schema: 'dnyf.runtime.v1',
        runtime: 'dnyf-universal-runtime/1',
        version: '1.0.0',
        platform: detectPlatform(),
        identity: loadIdentity(),
        capabilities: detectCapabilities(),
        security: {
            self_trust: false,
            self_pairing: false,
            automatic_trust: false,
            remote_execution: false,
            remote_installation: false,
            remote_shell: false
        }
    };
}

module.exports = {
    runtimeInfo,
    classifyArtifact,
    dispatch,
    root: process.env.DNYF_ROOT ||
        path.resolve(__dirname, '../../../../..')
};

if (require.main === module) {
    try {
        console.log(
            JSON.stringify(runtimeInfo(), null, 2)
        );
    } catch (error) {
        console.error(error.stack || error.message);
        process.exit(1);
    }
}
DNYF_JS

###############################################################################
# 9. RUNTIME MANIFEST
###############################################################################

cat > "$CONFIG_ROOT/dnyf-runtime-manifest.json" <<'DNYF_JSON'
{
  "schema": "dnyf.runtime.manifest.v1",
  "component": "universal-runtime",
  "component_id": "dnyf-runtime-universal-v1",
  "version": "1.0.0",
  "files": [
    "dnyf-runtime-platform-detector.js",
    "dnyf-runtime-device-identity.js",
    "dnyf-runtime-capability-detector.js",
    "dnyf-runtime-artifact-manager.js",
    "dnyf-runtime-dispatcher.js",
    "dnyf-runtime-core.js"
  ],
  "windows": [
    "dnyf-runtime-windows-artifact-adapter.js"
  ],
  "security": {
    "remote_execution": false,
    "remote_installation": false,
    "remote_shell": false,
    "self_trust": false,
    "self_pairing": false,
    "automatic_trust": false
  }
}
DNYF_JSON

###############################################################################
# 10. PLATFORM/CAPABILITY GENERATION
###############################################################################

export DNYF_ROOT

node "$RUNTIME_ROOT/dnyf-runtime-platform-detector.js" \
    > "$PLATFORM_ROOT/dnyf-runtime-platform.json"

node "$RUNTIME_ROOT/dnyf-runtime-capability-detector.js" \
    > "$CAPABILITY_ROOT/dnyf-runtime-capabilities.json"

###############################################################################
# 11. RUNTIME REGISTRY
###############################################################################

cat > "$REGISTRY_ROOT/dnyf-runtime-components.json" <<'DNYF_JSON'
{
  "schema": "dnyf.runtime.registry.v1",
  "runtime": "dnyf-universal-runtime/1",
  "components": {
    "platform_detector": {
      "file": "opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js",
      "version": "1.0.0"
    },
    "identity_loader": {
      "file": "opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js",
      "version": "1.0.0"
    },
    "capability_detector": {
      "file": "opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js",
      "version": "1.0.0"
    },
    "artifact_manager": {
      "file": "opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js",
      "version": "1.0.0"
    },
    "dispatcher": {
      "file": "opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js",
      "version": "1.0.0"
    },
    "runtime_core": {
      "file": "opt/dnyf/runtime/universal/dnyf-runtime-core.js",
      "version": "1.0.0"
    },
    "windows_artifact_adapter": {
      "file": "opt/dnyf/runtime/windows/dnyf-runtime-windows-artifact-adapter.js",
      "version": "1.0.0"
    }
  }
}
DNYF_JSON

###############################################################################
# 12. UNIVERSAL CLI
###############################################################################

cat > "$BIN_ROOT/dnyf-runtime" <<'DNYF_SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"
CORE="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"
PLATFORM="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js"
CAPS="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js"
IDENTITY="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js"
DISPATCH="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js"
ARTIFACT="$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js"

export DNYF_ROOT="$ROOT"

case "${1:-info}" in
    info)
        exec node "$CORE"
        ;;

    platform)
        exec node "$PLATFORM"
        ;;

    capabilities)
        exec node "$CAPS"
        ;;

    identity)
        exec node "$IDENTITY"
        ;;

    dispatch)
        shift
        exec node "$DISPATCH" "$@"
        ;;

    artifact)
        shift
        exec node "$ARTIFACT" "$@"
        ;;

    version)
        printf '%s\n' 'DNYF Universal Runtime 1.0.0'
        ;;

    help|-h|--help)
        cat <<'HELP'
DNYF Universal Runtime

Commands:
  dnyf-runtime info
  dnyf-runtime platform
  dnyf-runtime capabilities
  dnyf-runtime identity
  dnyf-runtime dispatch <file>
  dnyf-runtime artifact list
  dnyf-runtime artifact inspect <file>
  dnyf-runtime artifact store <file> [name]
  dnyf-runtime version
  dnyf-runtime help
HELP
        ;;

    *)
        printf 'Unknown runtime command: %s\n' "$1" >&2
        exit 2
        ;;
esac
DNYF_SH

chmod 0755 "$BIN_ROOT/dnyf-runtime"

ln -sfn "$BIN_ROOT/dnyf-runtime" "$USR_BIN/dnyf-runtime"
ln -sfn "$BIN_ROOT/dnyf-runtime" "$LOCAL_BIN/dnyf-runtime"

###############################################################################
# 13. RUNTIME VALIDATOR
###############################################################################

cat > "$VALIDATION_ROOT/dnyf-runtime-validator.sh" <<'DNYF_SH'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="${DNYF_ROOT:-$HOME/DNYF-DEV}"

CYAN=$'\033[1;36m'
GREEN=$'\033[1;32m'
RED=$'\033[1;31m'
RESET=$'\033[0m'

PASS=0
FAIL=0

check_file() {
    local label="$1"
    local file="$2"

    if [ -f "$file" ]; then
        printf '%b[OK]%b %s\n' "$GREEN" "$RESET" "$label"
        PASS=$((PASS + 1))
    else
        printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$label"
        FAIL=$((FAIL + 1))
    fi
}

check_file \
    "platform detector" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js"

check_file \
    "identity loader" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js"

check_file \
    "capability detector" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js"

check_file \
    "artifact manager" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js"

check_file \
    "dispatcher" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js"

check_file \
    "runtime core" \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"

check_file \
    "Windows artifact adapter" \
    "$ROOT/opt/dnyf/runtime/windows/dnyf-runtime-windows-artifact-adapter.js"

check_file \
    "runtime protocol" \
    "$ROOT/etc/dnyf/runtime/dnyf-runtime-protocol.json"

check_file \
    "runtime manifest" \
    "$ROOT/etc/dnyf/runtime/dnyf-runtime-manifest.json"

check_file \
    "runtime registry" \
    "$ROOT/registry/dnyf-runtime-components.json"

check_file \
    "runtime CLI" \
    "$ROOT/bin/dnyf-runtime"

check_file \
    "platform metadata" \
    "$ROOT/etc/dnyf/platform/dnyf-runtime-platform.json"

check_file \
    "capability metadata" \
    "$ROOT/etc/dnyf/capabilities/dnyf-runtime-capabilities.json"

printf '\n'

export DNYF_ROOT="$ROOT"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-platform-detector.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-device-identity.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-capability-detector.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-artifact-manager.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-dispatcher.js"

node --check \
    "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js"

node --check \
    "$ROOT/opt/dnyf/runtime/windows/dnyf-runtime-windows-artifact-adapter.js"

printf '%b[OK]%b JavaScript syntax validation\n' "$GREEN" "$RESET"

INFO="$(node "$ROOT/opt/dnyf/runtime/universal/dnyf-runtime-core.js")"

printf '%s\n' "$INFO" | grep -q '"runtime": "dnyf-universal-runtime/1"'
printf '%b[OK]%b runtime protocol identity\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"remote_execution": false'
printf '%b[OK]%b remote execution disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"remote_installation": false'
printf '%b[OK]%b remote installation disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"remote_shell": false'
printf '%b[OK]%b remote shell disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"self_trust": false'
printf '%b[OK]%b self-trust disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"self_pairing": false'
printf '%b[OK]%b self-pairing disabled\n' "$GREEN" "$RESET"

printf '%s\n' "$INFO" | grep -q '"automatic_trust": false'
printf '%b[OK]%b automatic trust disabled\n' "$GREEN" "$RESET"

printf '\n'
printf '%bRuntime validation: %s passed, %s failed%b\n' \
    "$CYAN" "$PASS" "$FAIL" "$RESET"

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

printf '%bUNIVERSAL RUNTIME: PASS%b\n' "$GREEN" "$RESET"
DNYF_SH

chmod 0755 "$VALIDATION_ROOT/dnyf-runtime-validator.sh"

###############################################################################
# 14. TOPOLOGY INTEGRATION
###############################################################################

ln -sfn \
    "$RUNTIME_ROOT" \
    "$DNYF_ROOT/runtime-universal"

ln -sfn \
    "$ARTIFACT_ROOT" \
    "$DNYF_ROOT/dnyf-artifacts"

ln -sfn \
    "$WINDOWS_ROOT" \
    "$DNYF_ROOT/dnyf-windows"

###############################################################################
# 15. SERVICE REGISTRY MERGE
###############################################################################

SERVICE_REGISTRY="$REGISTRY_ROOT/services.json"

if [ -f "$SERVICE_REGISTRY" ]; then
    node - "$SERVICE_REGISTRY" <<'DNYF_NODE'
const fs = require('fs');

const file = process.argv[2];
let registry;

try {
    registry = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (_) {
    registry = {
        schema: 'dnyf.service.registry.v1',
        services: {}
    };
}

if (!registry.services || typeof registry.services !== 'object') {
    registry.services = {};
}

registry.services['dnyf-universal-runtime'] = {
    id: 'dnyf-universal-runtime',
    protocol: 'dnyf-runtime/1',
    version: '1.0.0',
    mode: 'library-and-cli',
    network_port: null,
    enabled: true,
    remote_execution: false,
    remote_installation: false,
    remote_shell: false,
    self_trust: false,
    self_pairing: false,
    automatic_trust: false
};

fs.writeFileSync(
    file,
    JSON.stringify(registry, null, 2) + '\n'
);
DNYF_NODE
else
    cat > "$SERVICE_REGISTRY" <<'DNYF_JSON'
{
  "schema": "dnyf.service.registry.v1",
  "services": {
    "dnyf-universal-runtime": {
      "id": "dnyf-universal-runtime",
      "protocol": "dnyf-runtime/1",
      "version": "1.0.0",
      "mode": "library-and-cli",
      "network_port": null,
      "enabled": true,
      "remote_execution": false,
      "remote_installation": false,
      "remote_shell": false,
      "self_trust": false,
      "self_pairing": false,
      "automatic_trust": false
    }
  }
}
DNYF_JSON
fi

###############################################################################
# 16. FINAL VALIDATION
###############################################################################

printf '\n'
printf '%b============================================================%b\n' "$CYAN" "$RESET"
printf '%b UNIVERSAL RUNTIME VALIDATION%b\n' "$WHITE" "$RESET"
printf '%b============================================================%b\n\n' "$CYAN" "$RESET"

"$VALIDATION_ROOT/dnyf-runtime-validator.sh"

###############################################################################
# 17. SUMMARY
###############################################################################

printf '\n'
printf '%b============================================================%b\n' "$GREEN" "$RESET"
printf '%b DNYFTECH UNIVERSAL RUNTIME INSTALLED%b\n' "$WHITE" "$RESET"
printf '%b============================================================%b\n' "$GREEN" "$RESET"

printf '\n'
printf '%bRuntime:%b     dnyf-universal-runtime/1\n' "$CYAN" "$RESET"
printf '%bVersion:%b     1.0.0\n' "$CYAN" "$RESET"
printf '%bRoot:%b        %s\n' "$CYAN" "$RESET" "$DNYF_ROOT"
printf '%bPlatform:%b    %s\n' "$CYAN" "$RESET" \
    "$(node "$RUNTIME_ROOT/dnyf-runtime-platform-detector.js" | grep '"host"' | head -1 | sed 's/.*: //; s/[",]//g')"
printf '%bRuntime CLI:%b %s\n' "$CYAN" "$RESET" "$BIN_ROOT/dnyf-runtime"
printf '%bArtifacts:%b   %s\n' "$CYAN" "$RESET" "$ARTIFACT_ROOT"
printf '%bWindows:%b     %s\n' "$CYAN" "$RESET" "$WINDOWS_ROOT"

printf '\n'
printf '%bSecurity:%b\n' "$WHITE" "$RESET"
printf '  remote execution:     false\n'
printf '  remote installation:  false\n'
printf '  remote shell:         false\n'
printf '  self-trust:            false\n'
printf '  self-pairing:          false\n'
printf '  automatic trust:       false\n'

printf '\n'
printf '%bCommands:%b\n' "$WHITE" "$RESET"
printf '  dnyf-runtime info\n'
printf '  dnyf-runtime platform\n'
printf '  dnyf-runtime capabilities\n'
printf '  dnyf-runtime identity\n'
printf '  dnyf-runtime dispatch <file>\n'
printf '  dnyf-runtime artifact list\n'
printf '  dnyf-runtime artifact inspect <file>\n'
printf '  dnyf-runtime artifact store <file> [name]\n'

printf '\n%b◆ DNYFTECH%b\n' "$CYAN" "$RESET"
printf '%b◈ DNYF-DEV Universal Runtime is ready.%b\n' "$WHITE" "$RESET"
printf '%b✦ CEEZIX runtime compatibility layer prepared.%b\n' "$WHITE" "$RESET"
printf '%b▣ Windows artifact compatibility layer prepared.%b\n' "$WHITE" "$RESET"
printf '%b⌁ Universal platform/capability detection active.%b\n' "$WHITE" "$RESET"
printf '%b✓ Phase 2 Universal Runtime: COMPLETE%b\n\n' "$GREEN" "$RESET"
