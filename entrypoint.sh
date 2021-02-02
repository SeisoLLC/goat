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
      help 1
      ;;
    WARNING)
      >&2 echo -e "${!color}${1}:  ${2}${DEFAULT}"
      ;;
    *)
      echo -e "${!color}${1}:  ${2}${DEFAULT}"
      ;;
  esac
}

function setup() {
	git fetch origin main:main
}

function super_lint() {
  /action/lib/linter.sh
}

function seiso_lint() {
  npm install -g dockerfile_lint
  for file_name in $(git diff --name-only "${HEAD}" main); do
    if [[ "${file_name}" == "Dockerfile"* ]]; then
      dockerfile_lint -f "${file_name}" -r /usr/local/etc/oci_annotations.yml
    fi
  done
}

function check_links() {
  npm install -g markdown-link-check
  for file_name in $(git diff --name-only "${HEAD}" main); do
    if [[ "${file_name}" == *".md" ]]; then
      npx markdown-link-check --config /usr/local/etc/links.json --verbose "${file_name}"
    fi
  done
}

function check_spelling() {
  npm install -g cspell
  git diff --name-only main "${HEAD}" | xargs -L1 npx cspell -c /usr/local/etc/spelling.json -u -e /usr/local/etc/
}

function check_terraform() {
  image="seiso/easy_infra:latest"
  docker pull "${image}"
  docker run --rm "$(pwd):/iac/" "${image}" terraform validate
}


super_lint
