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
