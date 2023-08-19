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
  declare -r DEBUG='\033[0m'
  declare -r DEFAULT='\033[0m'
}

function feedback() {
  color="${1:-DEFAULT}"
  case "${1}" in
  ERROR)
    echo >&2 -e "${!color}${1}:  ${2}${DEFAULT}"
    ;;
  WARNING)
    echo >&2 -e "${!color}${1}:  ${2}${DEFAULT}"
    ;;
  *)
    if [[ "${1^^}" != "DEBUG" ]]; then
      echo -e "${!color}${1}:  ${2}${DEFAULT}"
    elif [[ "${1^^}" == "DEBUG" && -n "${LOG_LEVEL:+x}" && "${LOG_LEVEL^^}" == "DEBUG" ]]; then
      echo -e "${!color}${1}:  ${2}${DEFAULT}"
    fi
    ;;
  esac
}

function setup_environment() {
  # Set the preferred shell behavior
  shopt -s globstar

  # Set the default branch
  export DEFAULT_BRANCH="main"

  # Set workspace to /goat for local runs
  export DEFAULT_WORKSPACE="/goat"

  # Set default values for autofix
  export AUTO_FIX="true"
  export CURRENT_LINT_ROUND=1

  # Create variables for the various dictionary file paths
  export GLOBAL_DICTIONARY="/etc/opt/goat/seiso_global_dictionary.txt"
  export LINTER_CONFIG="/etc/opt/goat/linters.json"

  # Identify the correct relative path to use
  if [[ -d "${DEFAULT_WORKSPACE}/.git" ]]; then
    # Local / default use
    RELATIVE_PATH="${DEFAULT_WORKSPACE}"
  elif [[ -n "${GITHUB_WORKSPACE:+x}" ]]; then
    # GitHub Actions
    RELATIVE_PATH="${GITHUB_WORKSPACE}"
  elif [[ -d "/src/.git" ]]; then
    # Pre-commit
    RELATIVE_PATH="/src"
  else
    feedback ERROR "Unable to identify the right relative path to find the repo dictionary"
    exit 1
  fi

  export REPO_DICTIONARY="${RELATIVE_PATH}/.github/etc/dictionary.txt"

  if [[ -n ${JSCPD_CONFIG:+x} ]]; then
    feedback WARNING "JSCPD_CONFIG is set; not auto ignoring the goat submodule..."
  else
    # This should override the ignore in the config file and is primarily needed so that we can pass in the correct relative path while not excluding all of the
    # goat on the goat itself (i.e. we are avoiding **/goat/** in the config file)
    export INTERNAL_JSCPD_CONFIG="--config /etc/opt/goat/.jscpd.json --ignore \"**/.github/workflows/**,${RELATIVE_PATH}/goat/**\""
    export JSCPD_CONFIG="${INTERNAL_JSCPD_CONFIG}"
    feedback DEBUG "JSCPD_CONFIG was dynamically set to ${JSCPD_CONFIG}"
  fi

  #############
  # IMPORTANT: If you are changing any INPUT_ variables here, make sure to also update:
  # - README.md
  # - Task/**/Taskfile.yml (vars)
  # - action.yml
  #############

  if [[ ${INPUT_AUTO_FIX:-true} == "false" ]]; then
    # Let INPUT_AUTO_FIX override the autofix value. This allows for disabling autofix locally.
    AUTO_FIX="false"
  fi

  if [[ ${INPUT_DISABLE_MYPY:-} == "true" ]]; then
    export VALIDATE_PYTHON_MYPY="false"
  fi

  if [[ -n ${INPUT_EXCLUDE:+x} ]]; then
    export FILTER_REGEX_EXCLUDE="${INPUT_EXCLUDE}"
  fi

  # Default to info
  INPUT_LOG_LEVEL=${INPUT_LOG_LEVEL:-INFO}
  if [[ ${INPUT_LOG_LEVEL^^} =~ ^(ERROR|WARNING|INFO|DEBUG)$ ]]; then
    export LOG_LEVEL="${INPUT_LOG_LEVEL}"
    export ACTIONS_RUNNER_DEBUG="true"
  fi

  feedback DEBUG "Looking in ${REPO_DICTIONARY} for the dictionary.txt"
  feedback DEBUG "INPUT_AUTO_FIX is ${INPUT_AUTO_FIX:-not set}"
  feedback DEBUG "AUTO_FIX is ${AUTO_FIX:-not set}"
  feedback DEBUG "INPUT_DISABLE_MYPY is ${INPUT_DISABLE_MYPY:-not set}"
  feedback DEBUG "VALIDATE_PYTHON_MYPY is ${VALIDATE_PYTHON_MYPY:-not set}"
  feedback DEBUG "INPUT_EXCLUDE is ${INPUT_EXCLUDE:-not set}"
  feedback DEBUG "FILTER_REGEX_EXCLUDE is ${FILTER_REGEX_EXCLUDE:-not set}"
  feedback DEBUG "INPUT_LOG_LEVEL is ${INPUT_LOG_LEVEL:-not set}"
  feedback DEBUG "LOG_LEVEL is ${LOG_LEVEL:-not set}"

  # Sets up pyenv so that any linters ran via pipenv run can have an arbitrary python version
  # More details in https://github.com/pyenv/pyenv/tree/7b713a88c40f39139e1df4ed0ceb764f73767dac#advanced-configuration
  eval "$(pyenv init -)"

  declare -a linter_failures
  declare -a linter_successes
  declare -a linter_skipped
}

function check_environment() {
  # Check the GITHUB_BASE_REF (PRs only)
  if [[ ${GITHUB_ACTIONS:-false} == "true" && -n ${GITHUB_BASE_REF:+x} ]]; then
    mainline="${GITHUB_BASE_REF##*/}"
    if [[ ${mainline} != "main" ]]; then
      feedback ERROR "Base branch name is not main"
      exit 1
    fi
  fi

  # Ensure there is a repo dictionary
  if [[ ! -r "${REPO_DICTIONARY}" ]]; then
    feedback ERROR "Unable to read a repo dictionary at ${REPO_DICTIONARY}; does it exist?"
    exit 1
  fi

  # Ensure dictionaries don't have overlap
  overlap=$(comm -12 <(sort "${GLOBAL_DICTIONARY}" | tr '[:upper:]' '[:lower:]') \
    <(sort "${REPO_DICTIONARY}" | tr '[:upper:]' '[:lower:]'))
  if [[ "${overlap}" ]]; then
    feedback WARNING "The following words are already in the global dictionary:
${overlap}"
    feedback ERROR "Overlap was detected in the per-repo and global dictionaries"
    exit 1
  fi

  # Ensure dictionaries are sorted
  if ! sort -c "${REPO_DICTIONARY}" 2>/dev/null; then
    feedback ERROR "The repo dictionary must be sorted"
    exit 1
  fi
}

function detect_kubernetes_file() {
  # Seach for k8s-specific strings in files to determine which files to pass to kubeconform for linting
  # Here a return of 0 indicates the function did not find a string match and exits with a success code,
  # and 1 indicates the strings were found. This more aligns with a boolean-like response.
  local file="$1"

  if grep -q -v 'kustomize.config.k8s.io' "${file}" &&
    grep -q -v "tekton" "${file}" &&
    grep -q -E '^apiVersion:' "${file}" &&
    grep -q -E '^kind:' "${file}"; then
    return 1
  fi

  return 0
}

function detect_cloudformation_file() {
  # Search for AWS Cloud Formation-related strings in files to determine which files to pass to cfn-lint
  # Here a return of 0 indicates the function did not find a string match and exits with a success code,
  # and 1 indicates the string was found. This more aligns with a boolean-like response.
  local file="$1"

  # Searches for a string specific to AWS CF templates
  if grep -q 'AWSTemplateFormatVersion' "${file}" >/dev/null; then
    return 1
  fi

  # Search for AWS, Alexa Skills Kit, or Custom Cloud Formation syntax within the file
  if grep -q -E '(AWS|Alexa|Custom)::' "${file}" >/dev/null; then
    return 1
  fi

  return 0
}

function get_files_matching_filetype() {
  local filenames=("${@:3}")
  local linter_name="$2"
  local f_type="$1"

  declare -a matching_files=()

  for file in "${filenames[@]}"; do
    filename=$(basename "${file}")
    if [[ $filename == *"$f_type" ]]; then
      if [ "$linter_name" == "cfn-lint" ]; then
        if detect_cloudformation_file "${file}"; then
          continue
        fi
      fi
      if [ "$linter_name" == "kubeconform" ]; then
        if detect_kubernetes_file "${file}"; then
          continue
        fi
      fi
      if [ "$linter_name" == "actionlint" ]; then
        local action_path="${GITHUB_WORKSPACE:-.}/.github/workflows/"
        if [[ "${file}" != "${action_path}"* ]]; then
          continue
        fi
      fi
      matching_files+=("${file}")
    fi
  done

  echo "${matching_files[@]}"
}

function load_filetype_array() {
  local val=$1
  declare -a types

  val=$(echo "$val" | jq -r '.[]')
  while IFS= read -r filetype; do
    types+=("$filetype")
  done <<<"$val"

  echo "${types[@]}"
}

function has_autofix() {
  local lint_name=$1

  while IFS= read -r line; do
    name=$(echo "$line" | jq -r ".name")
    if [[ "$name" == "$lint_name" ]]; then
      if echo "$line" | jq -e '.autofix' > /dev/null; then
        # If linter has an autofix exit true bit
        return 1
      else
        return 0
      fi
    fi
  done < <(jq -c '.[]' "${LINTER_CONFIG}")
}

function lint_files() {
  # Turn the received string back into an object
  local -n linter_array="$1"
  local filetypes_to_lint=("${@:2}")
  local linter_args="${linter_array[args]}"
  local files_to_lint=""
  local env_var_name="${linter_array[env]}"

  if [ "${CURRENT_LINT_ROUND}" -eq 2 ] && ! has_autofix "${linter_array[name]}"; then
    linter_args="${linter_array[autofix]}"
  fi

  if [[ -v "${env_var_name}" ]]; then
    linter_args="${!env_var_name}"
    if [[ "${env_var_name}" == "JSCPD_CONFIG" && "${linter_args}" == "${INTERNAL_JSCPD_CONFIG}" ]]; then
      feedback DEBUG "Hit special case for JSCPD_CONFIG internal customization to allow dynamic ignores at runtime; not printing a warning"
    else
      feedback WARNING "The linter runtime for ${linter_array[name]} has been customized, which might have unwanted side effects. Use with caution."
    fi
  fi

  for type in "${filetypes_to_lint[@]}"; do
    if [[ $type == "all" ]]; then
      cmd="${linter_array[name]} $linter_args $(printf '%q ' "${included[@]}")"
      eval "$cmd" >>"${linter_array[logfile]}" 2>&1
      return
    fi

    files_to_lint="$(get_files_matching_filetype "$type" "${linter_array[name]}" "${included[@]}")"

    if [ "${#files_to_lint}" -eq 0 ]; then
      return
    fi

    for file in "${files_to_lint[@]}"; do
      if [[ "${linter_array[executor]+x}" ]]; then
        cmd="${linter_array[executor]} ${linter_array[name]} $linter_args ${file}"
      else
        cmd="${linter_array[name]} $linter_args ${file}"
      fi

      echo "$cmd" >>"${linter_array[logfile]}"
      eval "$cmd" >>"${linter_array[logfile]}" 2>&1
    done
  done
}

function seiso_lint() {
  echo -e "\nRunning Seiso Linter\n--------------------------\n"

  if [[ -n ${GITHUB_WORKSPACE:-} ]]; then
    echo "Setting ${GITHUB_WORKSPACE} as safe directory"
    git config --global --add safe.directory "${GITHUB_WORKSPACE}"
  fi

  # When run in a pipeline, move per-repo configurations into the right location at runtime so the goat finds them, overwriting the defaults.
  # This will handle hidden and non-hidden files, as well as sym links
  if [[ -d "${GITHUB_WORKSPACE:-.}/.github/linters" ]]; then
    cp -p "${GITHUB_WORKSPACE:-.}/.github/linters/"* "${GITHUB_WORKSPACE:-.}/.github/linters/".* /etc/opt/goat/ 2>/dev/null || true
  fi

  excluded=()
  included=()

  while read -r file; do
    if [[ -n ${FILTER_REGEX_EXCLUDE:+x} && "${file}" =~ ${FILTER_REGEX_EXCLUDE} ]]; then
      feedback INFO "${file} matched the exclusion regex of ${FILTER_REGEX_EXCLUDE}"
      excluded+=("${file}")
      continue
    else
      feedback DEBUG "${file} didn't match the exclusion regex of ${FILTER_REGEX_EXCLUDE:-not set}"
    fi
    included+=("${file}")
  done < <(find "${RELATIVE_PATH}" \( -path "${RELATIVE_PATH}/.git" -prune \) -o \( -type f -print \))

  declare -A pids

  while read -r line; do
    unset linter
    declare -A linter
    unset linter_filetypes
    declare -a linter_filetypes

    while IFS='=' read -r key value; do
      if [[ $key == "filetype" ]]; then
        linter_filetypes=("$(load_filetype_array "$value")")
        continue
      fi
      value=$(echo "$value" | tr -d "'" | tr -d '"')
      linter["$key"]=$value
    done < <(echo "$line" | jq -r 'to_entries|map("\(.key)=\(.value|tojson)")|.[]')

    linter[logfile]="/opt/goat/log/${linter[name]}.log"

    if [[ -v VALIDATE_PYTHON_MYPY && "${VALIDATE_PYTHON_MYPY,,}" == "false" && "${linter[name]}" == "mypy" ]]; then
      echo "mypy linter has been disabled"
      linter_skipped+=("${linter[name]}")
      continue
    fi

    echo "===============================" >>"${linter[logfile]}"
    echo "Running linter: ${linter[name]}"
    echo "${linter[name]^^}" >>"${linter[logfile]}"

    # The string "linter" gets dereferenced back into a variable on the receiving end
    lint_files linter "${linter_filetypes[@]}" &

    pid=$!
    pids["$pid"]="${linter[name]}"

    echo "-------------------------------" >>"${linter[logfile]}"
  done < <(jq -c '.[]' "${LINTER_CONFIG}")

  for p in "${!pids[@]}"; do
    set +e
    wait "$p"
    exit_code=$?
    set -e

    if [ "$exit_code" -gt 0 ]; then
      cat "/opt/goat/log/${pids[$p]}.log"
      linter_failures+=("${pids[$p]}")
    else
      linter_successes+=("${pids[$p]}")
    fi
  done
}

function rerun_lint() {
  local failed_linter="$1"
  unset rerun_linter
  declare -A rerun_linter
  unset rerun_filetypes
  declare -a rerun_filetypes

  while IFS= read -r line; do
    name=$(echo "$line" | jq -r ".name")
    if [[ "$name" == "$failed_linter" ]]; then
      feedback INFO "Linter $failed_linter found errors and has a fix option. Attempting fix."

      while IFS='=' read -r key value; do
        if [[ $key == "filetype" ]]; then
          rerun_filetypes=("$(load_filetype_array "$value")")
          continue
        fi
        value=$(echo "$value" | tr -d "'" | tr -d '"')
        rerun_linter["$key"]=$value
      done < <(echo "$line" | jq -r 'to_entries|map("\(.key)=\(.value|tojson)")|.[]')

      rerun_linter[logfile]="/opt/goat/log/rerun_${rerun_linter[name]}.log"
    fi
  done < <(jq -c '.[]' "${LINTER_CONFIG}")

  echo "===============================" >>"${rerun_linter[logfile]}"
  echo "Re-running linter: ${rerun_linter[name]}"
  echo "${rerun_linter[name]^^}" >>"${rerun_linter[logfile]}"

  # The string "rerun_linter" gets dereferenced back into a variable on the receiving end
  lint_files rerun_linter "${rerun_filetypes[@]}"

  echo "-------------------------------" >>"${rerun_linter[logfile]}"
}

start=$(date +%s)
setup_environment
check_environment
seiso_lint
end=$(date +%s)
runtime=$((end - start))

echo -e "\nScanned ${#included[@]} files in ${runtime} seconds"
echo -e "Excluded ${#excluded[@]} files\n"

if [ -n "${linter_successes[*]}" ]; then
  for success in "${linter_successes[@]}"; do
    feedback INFO "$success completed successfully"
  done
fi

declare -a rerun_linter_failures
declare -a rerun_linter_successes
failed_lint="false"

if [ -n "${linter_failures[*]}" ]; then
  if [[ ${AUTO_FIX:-true} == "true" ]]; then
    CURRENT_LINT_ROUND=2
    declare -A rerun_pids

    for failure in "${linter_failures[@]}"; do
      if ! has_autofix "$failure"; then
        rerun_lint "$failure" &
        rerun_pid=$!
        rerun_pids["$rerun_pid"]="$failure"
        continue
      fi

      feedback ERROR "$failure found errors"
      failed_lint="true"
    done

    for p in "${!rerun_pids[@]}"; do
      set +e
      wait "$p"
      exit_code=$?
      set -e

      if [ "$exit_code" -gt 0 ]; then
        rerun_linter_failures+=("${rerun_pids[$p]}")
      else
        rerun_linter_successes+=("${rerun_pids[$p]}")
      fi

      cat "/opt/goat/log/rerun_${rerun_pids[$p]}.log"
    done
  else
    for failure in "${linter_failures[@]}"; do
      feedback ERROR "$failure found errors"
    done

    failed_lint="true"
  fi
fi

if [[ -n "${rerun_linter_successes[*]}" && -n $(git status -s) ]]; then
  for success in "${rerun_linter_successes[@]}"; do
    if [[ ${CI:-false} == "true" ]]; then
      feedback ERROR "$success detected issues but they can be **automatically fixed**; run 'task lint' locally, commit, and push."
      continue
    fi

    feedback ERROR "Autofix of $success errors completed successfully. Check it out and commit the changes."
  done
  failed_lint="true"
fi

if [[ -n "${rerun_linter_failures[*]}" ]]; then
  for failure in "${rerun_linter_failures[@]}"; do
    if [[ ${CI:-false} == "true" ]]; then
      feedback ERROR "Attempts to autofix $failure errors were unsuccessful. Please correct manually."
      continue
    fi

    feedback ERROR "Attempts to autofix $failure errors were unsuccessful. Your local directory might be dirty with partial fixes."
  done

  failed_lint="true"
fi

if [[ "$failed_lint" == "true" ]]; then
  feedback ERROR "Linters found errors"
  exit 1
fi

feedback INFO "Linters found no errors."
