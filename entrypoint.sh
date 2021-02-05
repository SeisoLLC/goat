#!/usr/bin/env bash

set -o errtrace
set -o nounset
set -o errexit
set -o pipefail

# shellcheck disable=SC2034
{
  declare -r FATAL='\033[0;31m'
  declare -r ERROR='\033[0;31m'
  declare -r WARNING='\033[0;33m'
  declare -r INFO='\033[0m'
  declare -r DEFAULT='\033[0m'
}

function feedback() {
  color="${1:-DEFAULT}"
  case "${1}" in
    FATAL)
      >&2 echo -e "${!color}${1}:  ${2}${DEFAULT}"
      exit 1
      ;;
    ERROR)
      >&2 echo -e "${!color}${1}:  ${2}${DEFAULT}"
      exit 1
      ;;
    WARNING)
      >&2 echo -e "${!color}${1}:  ${2}${DEFAULT}"
      ;;
    *)
      echo -e "${!color}${1}:  ${2}${DEFAULT}"
      ;;
  esac
}

function check_environment() {
# Check the GITHUB_BASE_REF (PRs only)
  if [[ "${GITHUB_ACTIONS-}" == "true" && -n "${GITHUB_BASE_REF-}" ]]; then
    mainline="${GITHUB_BASE_REF-##*/}"
    if [[ "${mainline}" != "main" ]]; then
      feedback ERROR "Base branch name is not main"
    fi
  fi
}

function super_lint() {
  /action/lib/linter.sh
}

function seiso_lint() {
  # Check Dockerfiles
  npm install -g dockerfile_lint
  while read -r file; do
    dockerfile_lint -f "${file}" -r /etc/opt/goat/oci.yml
  done < <(find . -type f -name "*Dockerfile*")

  # Check .md file spelling
  npm install -g cspell
  npx cspell -c /etc/opt/goat/cspell.json -- **/*.md

  # Check .md file links
  npm install -g markdown-link-check
  while read -r file; do
    npx markdown-link-check --config /etc/opt/goat/links.json --verbose "${file}"
  done < <(find . -type f -name "*.md")
}


check_environment
super_lint
seiso_lint
