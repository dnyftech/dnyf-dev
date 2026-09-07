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
        return Math.max(1, os.cpus().length);
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
