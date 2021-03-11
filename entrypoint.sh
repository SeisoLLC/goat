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

function setup_environment() {
  # Set the default branch
  export DEFAULT_BRANCH="main"

  # Turn off the possum
  export SUPPRESS_POSSUM="true"

  # Set workspace to /goat/ for local runs
  export DEFAULT_WORKSPACE="/goat"

  # Map certain environment variables
  if [[ "${INPUT_DISABLE_TERRASCAN-}" == "true" ]]; then
    export VALIDATE_TERRAFORM_TERRASCAN="false"
  fi

  if [[ -n "${INPUT_EXCLUDE+x}" ]]; then
    export FILTER_REGEX_EXCLUDE="${INPUT_EXCLUDE}"
  fi
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
  excluded=()
  included=()

  npm install -g dockerfile_lint \
                 cspell \
                 markdown-link-check

  while read -r file; do
    # Apply filter with =~ to ensure it is aligned with github/super-linter
    if [[ -n "${INPUT_EXCLUDE+x}" && "${file}" =~ ${INPUT_EXCLUDE} ]]; then
      excluded+=("${file}")
      continue
    fi

    included+=("${file}")

    # Check Dockerfiles
    if [[ "${file}" = *Dockerfile ]]; then
      dockerfile_lint -f "${file}" -r /etc/opt/goat/oci.yml
    fi

    # Check .md file spelling and links
    if [[ "${file}" = *.md ]]; then
      npx cspell -c /etc/opt/goat/cspell.config.js -- "${file}"
      npx markdown-link-check --config /etc/opt/goat/links.json --verbose "${file}"
    fi
  done < <(find . -path "./.git" -prune -or -type f)

  echo "Scanned ${#included[@]} files"
  echo "Excluded ${#excluded[@]} files"
}


setup_environment
check_environment
super_lint
seiso_lint
