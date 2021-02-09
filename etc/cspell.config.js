'use strict';

if (process.env.GITHUB_WORKSPACE) {
  const BASEPATH = `${process.env['GITHUB_WORKSPACE']}`
} else {
  const BASEPATH = '.'
}

/** @type { import("@cspell/cspell-types").CSpellUserSettings } */
const cspell = {
    language: "en",
    dictionaries: [
        "bash",
        "companies",
        "cpp",
        "csharp",
        "css",
        "en-gb",
        "en_US",
        "go",
        "html",
        "latex",
        "misc",
        "node",
        "npm",
        "per-repository dictionary",
        "php",
        "powershell",
        "python",
        "seiso global dictionary",
        "softwareTerms",
        "typescript"
    ],
    dictionaryDefinitions: [
        {
            name: 'per-repository dictionary',
            path: `${BASEPATH}/.github/etc/dictionary.txt`,
        },
        {
            name: 'seiso global dictionary',
            path: `./seiso_global_dictionary.txt`,
        },
    ],
    minWordLength: 4,
    flagWords: [
        "blacklist",
        "master",
        "slave",
        "whitelist"
    ]
};

module.exports = cspell;
