'use strict';

const fs = require('fs');
const path = require('path');

function resolveRoot() {
    return process.env.DNYF_ROOT ||
        path.resolve(__dirname, '../../../../..');
}

function candidateIdentityFiles() {
    const root = resolveRoot();

    return [
        process.env.DNYF_IDENTITY_FILE,

        path.join(
            root,
            'opt/dnyf/runtime/secure/identity/identity.json'
        ),

        path.join(
            root,
            'identity/identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/identity/identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/security/identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/auth/identity.json'
        ),

        path.join(
            root,
            'opt/dnyf/config/identity.json'
        ),

        path.join(
            root,
            'opt/dnyf/config/dnyf-identity.json'
        ),

        path.join(
            root,
            'etc/dnyf/device-identity.json'
        )
    ].filter(Boolean);
}

function readIdentity(file) {
    const data = JSON.parse(
        fs.readFileSync(file, 'utf8')
    );

    if (
        !data ||
        typeof data !== 'object' ||
        typeof data.device_id !== 'string' ||
        data.device_id.trim() === ''
    ) {
        throw new Error(
            `Invalid DNYF identity authority: ${file}`
        );
    }

    return {
        device_id: String(data.device_id)
            .trim()
            .toLowerCase(),

        fingerprint: data.fingerprint
            ? String(data.fingerprint)
                .trim()
                .toLowerCase()
            : null,

        public_key: data.public_key || null,

        algorithm: data.algorithm || 'Ed25519',

        source: file
    };
}

function loadIdentity() {
    const candidates = candidateIdentityFiles();

    const errors = [];

    for (const file of candidates) {
        try {
            if (!fs.existsSync(file)) {
                continue;
            }

            return readIdentity(file);
        } catch (error) {
            errors.push(
                `${file}: ${error.message}`
            );
        }
    }

    const detail = errors.length
        ? `\n${errors.join('\n')}`
        : '';

    throw new Error(
        'DNYF canonical cryptographic identity could not be loaded.' +
        detail
    );
}

if (require.main === module) {
    process.stdout.write(
        JSON.stringify(loadIdentity(), null, 2) + '\n'
    );
}

module.exports = {
    resolveRoot,
    candidateIdentityFiles,
    loadIdentity
};
