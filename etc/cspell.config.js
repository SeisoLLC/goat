'use strict'

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
      path: `${process.env.GITHUB_WORKSPACE ? process.env.GITHUB_WORKSPACE : '.'}/.github/etc/dictionary.txt`
    },
    {
      name: 'seiso global dictionary',
      path: './seiso_global_dictionary.txt'
    }
  ],
  flagWords: [
    'blacklist',
    'master',
    'slave',
    'whitelist'
  ],
  ignoreRegExpList: [
    "/.*pairwise master key.*/"
  ],
  minWordLength: 4
}

module.exports = cspell
