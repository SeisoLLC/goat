'use strict'

let per_repo_dictionary_file;

if (process.env.GITHUB_WORKSPACE) {
  per_repo_dictionary_file = `${process.env.GITHUB_WORKSPACE}/.github/etc/dictionary.txt`;
} else if (process.env.BITBUCKET_CLONE_DIR) {
  per_repo_dictionary_file = `${process.env.BITBUCKET_CLONE_DIR}/dictionary.txt`;
} else {
  /** Assume it's running local and use .github **/
  per_repo_dictionary_file = '/goat/.github/etc/dictionary.txt';
}

/** @type { import("@cspell/cspell-types").CSpellUserSettings } */
const cspell = {
  language: 'en',
  dictionaries: [
    'bash',
    'companies',
    'cpp',
    'csharp',
    'css',
    'en-gb',
    'en_US',
    'go',
    'html',
    'latex',
    'misc',
    'node',
    'npm',
    'per-repository dictionary',
    'php',
    'powershell',
    'python',
    'seiso global dictionary',
    'softwareTerms',
    'typescript'
  ],
  dictionaryDefinitions: [
    {
      name: 'per-repository dictionary',
      path: per_repo_dictionary_file,
    },
    {
      name: 'seiso global dictionary',
      path: './seiso_global_dictionary.txt'
    }
  ],
  flagWords: [
    'blacklist',
    'blacklisted',
    'blacklisting',
    'master',
    'slave',
    'whitelist',
    'whitelisted',
    'whitelisting'
  ],
  ignoreRegExpList: [
    '/.*pairwise master key.*/',
    '/.*--ssid-whitelist.*/'
  ],
  minWordLength: 4
}

module.exports = cspell
