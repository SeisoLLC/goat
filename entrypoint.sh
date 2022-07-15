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
  else
    echo "The provided LOG_LEVEL of ${INPUT_LOG_LEVEL:-null or unset} is not valid"
  fi

  export ENABLE_SCORECARD="false"
  if [[ "${INPUT_ENABLE_SCORECARD:-}" == "true" ]]; then
      export ENABLE_SCORECARD="true"
  fi

  export GITHUB_AUTH_TOKEN=$INPUT_REPO_PAT

  export SCORECARD_RESULTS_FILE="$INPUT_SCORECARD_RESULTS_FILE"
  
  export SCORECARD_RESULTS_FORMAT="$INPUT_SCORECARD_RESULTS_FORMAT"
  
  export SCORECARD_PUBLISH_RESULTS="$INPUT_SCORECARD_PUBLISH_RESULTS"

  if [[ -n ${GITHUB_WORKSPACE:-} ]]; then
    echo "Setting ${GITHUB_WORKSPACE} as safe directory"
    git config --global --add safe.directory "${GITHUB_WORKSPACE}"
  fi
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

function seiso_lint() {
  excluded=()
  included=()

  while read -r file; do
    # Apply filter with =~ to ensure it is aligned with github/super-linter
    if [[ -n ${INPUT_EXCLUDE:+x} && "${file}" =~ ${INPUT_EXCLUDE} ]]; then
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

function run_scorecard() {

  if [[ $ENABLE_SCORECARD == "false" ]]; then
      echo "OSSF Scorecard not enabled!"
      return
  fi

  echo "OSSF Scorecard enabled!"
  export ENABLE_SARIF=1
  export SCORECARD_BIN=/opt/goat/bin/scorecard

  if ! [[ -z "${INPUT_SCORECARD_POLICY_FILE:-}" ]]; then
    export SCORECARD_POLICY_FILE=${GITHUB_WORKSPACE:-/goat}/$INPUT_SCORECARD_POLICY_FILE
  else
    export SCORECARD_POLICY_FILE="/etc/opt/goat/seiso_scorecard_policy.yml"  
  fi

  if [[ -z $GITHUB_AUTH_TOKEN ]]; then
    echo "Please provide a personal access token for you repo with the correct access."
    return
  fi

  status_code=$(curl -s -H "Authorization: Bearer ${GITHUB_AUTH_TOKEN}" https://api.github.com/repos/"$GITHUB_REPOSITORY" -o repo_info.json -w '%{http_code}')
  if [[ $status_code -lt 200 ]] || [[ $status_code -ge 300 ]]; then
      error_msg=$(jq -r .message repo_info.json 2>/dev/null || echo 'unknown error')
      echo "Failed to get repository information from GitHub, response $status_code: $error_msg"
      echo "$(<repo_info.json)"
      rm repo_info.json
      exit 1;
  fi

  export SCORECARD_PRIVATE_REPOSITORY="$(cat repo_info.json | jq -r '.private')"
  export SCORECARD_DEFAULT_BRANCH="refs/heads/$(cat repo_info.json | jq -r '.default_branch')"

  if [[ -z $SCORECARD_RESULTS_FILE ]]; then
    echo "Please provide a scorecard results file."
    return
  fi

  if [[ "$SCORECARD_PRIVATE_REPOSITORY" == "true" ]]; then
    export SCORECARD_PUBLISH_RESULTS="false"
  fi

  if [[ "$SCORECARD_RESULTS_FORMAT" != "sarif" ]]; then
    unset SCORECARD_POLICY_FILE
  fi

  if [[ "$GITHUB_EVENT_NAME" != "pull_request"* ]] && [[ "$GITHUB_REF" != "$SCORECARD_DEFAULT_BRANCH" ]]; then
    echo "$GITHUB_REF not supported with '$GITHUB_EVENT_NAME' event."
    echo "Only the default branch '$SCORECARD_DEFAULT_BRANCH' is supported"
    exit 1
  fi

  if [ -z ${SCORECARD_POLICY_FILE+x} ]; then
    $SCORECARD_BIN --local . --format "$SCORECARD_RESULTS_FORMAT" --show-details > "$SCORECARD_RESULTS_FILE"
  else
    $SCORECARD_BIN --local . --format "$SCORECARD_RESULTS_FORMAT" --show-details --policy "$SCORECARD_POLICY_FILE" > "$SCORECARD_RESULTS_FILE"
  fi

  if [[ "$SCORECARD_RESULTS_FORMAT" != "default" ]]; then
    jq '.' "$SCORECARD_RESULTS_FILE"
  fi

}

setup_environment
check_environment
super_lint
seiso_lint
run_scorecard