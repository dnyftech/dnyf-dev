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
