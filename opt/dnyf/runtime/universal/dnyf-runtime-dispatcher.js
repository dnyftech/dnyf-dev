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
