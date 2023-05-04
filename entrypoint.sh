#!/usr/bin/env bash

set -o errtrace
set -o nounset
set -o errexit
set -o pipefail

# shellcheck disable=SC2034
{
  declare -r ERROR='\033[0;31m'
  declare -r WARNING='\033[0;33m'
  declare -r INFO='\033[0m'
  declare -r DEFAULT='\033[0m'
}

function feedback() {
  color="${1:-DEFAULT}"
  case "${1}" in
    ERROR)
      >&2 echo -e "${!color}${1}:  ${2}${DEFAULT}"
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
  # Set the preferred shell behavior
  shopt -s globstar

  # Set the default branch
  export DEFAULT_BRANCH="main"

  # Turn off the possum
  export SUPPRESS_POSSUM="true"

  # Set workspace to /goat/ for local runs
  export DEFAULT_WORKSPACE="/goat"

  # Create variables for the various dictionary file paths
  export GLOBAL_DICTIONARY="/etc/opt/goat/seiso_global_dictionary.txt"
  export REPO_DICTIONARY="${GITHUB_WORKSPACE:-/goat}/.github/etc/dictionary.txt"

  # Map certain environment variables
  if [[ "${INPUT_DISABLE_TERRASCAN:-}" == "true" ]]; then
    export VALIDATE_TERRAFORM_TERRASCAN="false"
  fi

  if [[ "${INPUT_DISABLE_MYPY:-}" == "true" ]]; then
    export VALIDATE_PYTHON_MYPY="false"
  fi

  if [[ -n ${INPUT_EXCLUDE:+x} ]]; then
    export FILTER_REGEX_EXCLUDE="${INPUT_EXCLUDE}"
  fi

  if [[ "${INPUT_LOG_LEVEL:-}" =~ ^(ERROR|WARN|NOTICE|VERBOSE|DEBUG|TRACE)$ ]]; then
    export LOG_LEVEL="${INPUT_LOG_LEVEL}"
    export ACTIONS_RUNNER_DEBUG="true"
  else
    echo "The provided LOG_LEVEL of ${INPUT_LOG_LEVEL:-null or unset} is not valid"
  fi

  if [[ -n ${GITHUB_WORKSPACE:-} ]]; then
    echo "Setting ${GITHUB_WORKSPACE} as safe directory"
    git config --global --add safe.directory "${GITHUB_WORKSPACE}"

  fi

  # When run in a pipeline, move per-repo configurations into the right location at runtime so super-linter finds them, overwriting the defaults.
  # This will handle hidden and non-hidden files, as well as sym links
  cp -p "${GITHUB_WORKSPACE:-.}/.github/linters/"* "${GITHUB_WORKSPACE:-.}/.github/linters/".* /etc/opt/goat/ || true
}

function check_environment() {
  # Check the GITHUB_BASE_REF (PRs only)
  if [[ "${GITHUB_ACTIONS:-false}" == "true" && -n ${GITHUB_BASE_REF:+x} ]]; then
    mainline="${GITHUB_BASE_REF##*/}"
    if [[ "${mainline}" != "main" ]]; then
      feedback ERROR "Base branch name is not main"
    fi
  fi

  # Ensure dictionaries don't have overlap
  overlap=$(comm -12 <(sort "${GLOBAL_DICTIONARY}" | tr '[:upper:]' '[:lower:]') \
                     <(sort "${REPO_DICTIONARY}"   | tr '[:upper:]' '[:lower:]'))
  if [[ "${overlap}" ]]; then
    feedback WARNING "The following words are already in the global dictionary:
${overlap}"
    feedback ERROR "Overlap was detected in the per-repo and global dictionaries"
  fi
}

function super_lint() {
  /action/lib/linter.sh
}

function get_files_matching_filetype() {
  local filetype="$1"
  shift
  local filenames=("$@")
  matching_files=()

  for file in "${filenames[@]}"; do
    filename=$(basename "$file")
    
    if [[ "$filename" == *"$filetype" ]]; then
      matching_files+=("$file")
    fi
  done
  echo "${matching_files[@]}"
}

function check_linter_exit_code() {
  local return="$1"
  local name="$2"

  if [[ "${return:-1}" != 0 ]]; then
    linter_exit_codes+=(["$name"]="${return}")
  else
    feedback INFO "$name completed successfully" 
  fi
}

function lint_files() {
  if [[ "${linter[filetype]}" = "all" ]]; then
    cmd="${linter[name]} ${linter[args]}"
    eval "$cmd" >> "${linter[logfile]}" 2>&1
  else
    for file in $(get_files_matching_filetype "${linter[filetype]}" "${included[@]}"); do 
      if [[ "${linter[executor]+x}" ]]; then
        cmd="${linter[executor]} ${linter[name]} ${linter[args]} ${file}"
      else
        cmd="${linter[name]} ${linter[args]} ${file}"
      fi
      eval "$cmd" >> "${linter[logfile]}" 2>&1
    done
  fi
}

function seiso_lint() {
  echo -e "\nRunning Seiso Linter\n--------------------------\n"

  excluded=()
  included=()

  while read -r file; do
    if [[ -n ${INPUT_EXCLUDE:+x} && "${file}" =~ ${INPUT_EXCLUDE} ]]; then
      excluded+=("${file}")
      continue
    fi
    included+=("${file}")
  done < <(find . -path "./.git" -prune -o -type f)
  
  declare -gA linter_exit_codes
  declare -gA pids

  input="/etc/opt/goat/linters.json"

  while read -r line; do
    if [[ $line == \#* ]]; then
      continue
    fi
    
    unset linter
    declare -gA linter
 
    while IFS='=' read -r key value; do
      value=$(echo "$value" | tr -d "'")
      linter["$key"]=$value
    done < <(echo "$line" | jq -r 'to_entries|map("\(.key)=\(.value|tostring)")|.[]')
        
    linter+=([logfile]="/opt/goat/log/${linter[name]}.log")

    echo "===============================" >> "${linter[logfile]}"
    echo "Running linter: ${linter[name]}"
    echo "${linter[name]^^}" >>"${linter[logfile]}"

    lint_files & 
    pid=$!
    pids["$pid"]+="${linter[name]}"

    echo "-------------------------------" >> "${linter[logfile]}"
  done < <(jq -c '.[]' $input)

  for p in "${!pids[@]}"; do
    set +e
    wait "$p"
    exit_code=$?
    check_linter_exit_code "$exit_code" "${pids[$p]}"
    set -e
  done
  
  echo -e "\nScanned ${#included[@]} files"
  echo -e "Excluded ${#excluded[@]} files\n"
}

setup_environment
check_environment

superlinter_logfile="/opt/goat/log/super-linter.log"

echo -e "\nRunning Super-Linter\n--------------------------\n"
echo "===============================" >> "$superlinter_logfile"
echo "SUPER-LINTER" >> "$superlinter_logfile"

set +e
super_linter_result=$(super_lint >> "$superlinter_logfile" 2>&1; echo $?)
set -e

echo "-------------------------------" >> "$superlinter_logfile"

check_linter_exit_code "$super_linter_result" "super-linter"
seiso_lint

linter_failed="false"

for lint in "${!linter_exit_codes[@]}"; do
  if [[ "${linter_exit_codes[$lint]}" -gt 0 ]]; then
    linter_failed="true"
    cat "/opt/goat/log/$lint.log"
    message="discovered errors"
  fi
  feedback ERROR "$lint $message"
done

if [ "${linter_failed:-false}" == "true" ]; then
  feedback ERROR "Linting failed."
  exit 1
else
  feedback INFO "Linters found no errors."
  exit 0
fi