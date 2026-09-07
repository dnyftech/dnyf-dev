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
