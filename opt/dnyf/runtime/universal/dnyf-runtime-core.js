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
