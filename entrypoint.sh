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
		echo >&2 -e "${!color}${1}:  ${2}${DEFAULT}"
		;;
	WARNING)
		echo >&2 -e "${!color}${1}:  ${2}${DEFAULT}"
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

	# Set workspace to /goat/ for local runs
	export DEFAULT_WORKSPACE="/goat"

	# Create variables for the various dictionary file paths
	export GLOBAL_DICTIONARY="/etc/opt/goat/seiso_global_dictionary.txt"
	export REPO_DICTIONARY="${GITHUB_WORKSPACE:-/goat}/.github/etc/dictionary.txt"

	if [[ ${INPUT_DISABLE_MYPY-} == "true" ]]; then
		export VALIDATE_PYTHON_MYPY="false"
	fi

	if [[ -n ${INPUT_EXCLUDE:+x} ]]; then
		export FILTER_REGEX_EXCLUDE="${INPUT_EXCLUDE}"
	fi

	if [[ ${INPUT_LOG_LEVEL:='VERBOSE'} =~ ^(ERROR|WARN|NOTICE|VERBOSE|DEBUG|TRACE)$ ]]; then
		export LOG_LEVEL="${INPUT_LOG_LEVEL}"
		export ACTIONS_RUNNER_DEBUG="true"
	fi

	declare -a linter_failures
	declare -a linter_successes
}

function check_environment() {
	# Check the GITHUB_BASE_REF (PRs only)
	if [[ ${GITHUB_ACTIONS:-false} == "true" && -n ${GITHUB_BASE_REF:+x} ]]; then
		mainline="${GITHUB_BASE_REF##*/}"
		if [[ ${mainline} != "main" ]]; then
			feedback ERROR "Base branch name is not main"
		fi
	fi

	# Ensure dictionaries don't have overlap
	overlap=$(comm -12 <(sort "${GLOBAL_DICTIONARY}" | tr '[:upper:]' '[:lower:]') \
		<(sort "${REPO_DICTIONARY}" | tr '[:upper:]' '[:lower:]'))
	if [[ "${overlap}" ]]; then
		feedback WARNING "The following words are already in the global dictionary:
${overlap}"
		feedback ERROR "Overlap was detected in the per-repo and global dictionaries"
	fi
}

function detect_kubernetes_file() {
	# Seach for k8s-specific strings in files to determine which files to pass to kubeconform for linting
	# Here a return of 0 indicates the function did not find a string match and exits with a success code,
	# and 1 indicates the strings were found. This more aligns with a boolean-like response.
	local file="$1"

	if grep -q -v 'kustomize.config.k8s.io' "${file}" &&
		grep -q -v "tekton" "${file}" &&
		grep -q -E '(apiVersion):' "${file}" &&
		grep -q -E '(kind):' "${file}"; then
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
	local filenames=("$@")
	declare -a matching_files=()

	for filetype in "${linter_filetypes[@]}"; do
		for file in "${filenames[@]}"; do
			filename=$(basename "${file}")
			if [[ $filename == *"$filetype" ]]; then
				if [ "${linter[name]}" == "cfn-lint" ]; then
					if detect_cloudformation_file "${file}"; then
						continue
					fi
				fi
				if [ "${linter[name]}" == "kubeconform" ]; then
					if detect_kubernetes_file "${file}"; then
						continue
					fi
				fi
				if [ "${linter[name]}" == "actionlint" ]; then
					local action_path="${GITHUB_WORKSPACE:-.}/.github/workflows/"
					if [[ "${file}" != "${action_path}"* ]]; then
						continue
					fi
				fi
				matching_files+=("${file}")
			fi
		done
	done

	echo "${matching_files[@]}"
}

function lint_files() {
	local linter_args="${linter[args]}"
	local files_to_lint=""

	if [[ -v "${linter[env]}" && -n "${!linter[env]}" ]]; then
		linter_args="${!linter[env]}"
	fi

	for type in "${linter_filetypes[@]}"; do
		if [[ $type == "all" ]]; then
			cmd="${linter[name]} $linter_args"
			eval "$cmd" >>"${linter[logfile]}" 2>&1
			return
		fi
	done

	files_to_lint="$(get_files_matching_filetype "${included[@]}")"

	if [ "${#files_to_lint}" -eq 0 ]; then
		return
	fi

	for file in "${files_to_lint[@]}"; do
		if [[ "${linter[executor]+x}" ]]; then
			cmd="${linter[executor]} ${linter[name]} $linter_args ${file}"
		else
			cmd="${linter[name]} $linter_args ${file}"
		fi

		echo "$cmd" >>"${linter[logfile]}"
		eval "$cmd" >>"${linter[logfile]}" 2>&1
		return
	done
}

function seiso_lint() {
	echo -e "\nRunning Seiso Linter\n--------------------------\n"

	if [[ -n ${GITHUB_WORKSPACE:-} ]]; then
		echo "Setting ${GITHUB_WORKSPACE} as safe directory"
		git config --global --add safe.directory "${GITHUB_WORKSPACE}"
	fi

	# When run in a pipeline, move per-repo configurations into the right location at runtime so super-linter finds them, overwriting the defaults.
	# This will handle hidden and non-hidden files, as well as sym links
	if [[ -d "${GITHUB_WORKSPACE:-.}/.github/linters" ]]; then
		cp -p "${GITHUB_WORKSPACE:-.}/.github/linters/"* "${GITHUB_WORKSPACE:-.}/.github/linters/".* /etc/opt/goat/ || true
	fi

	excluded=()
	included=()

	while read -r file; do
		if [[ -n ${INPUT_EXCLUDE:+x} && "${file}" =~ ${INPUT_EXCLUDE} ]]; then
			excluded+=("${file}")
			continue
		fi
		included+=("$file")
	done < <(find . \( -path "./.git" -prune \) -o \( -type f -print \))

	declare -A pids

	input="/etc/opt/goat/linters.json"

	while read -r line; do
		unset linter
		declare -gA linter
		unset linter_filetypes
		declare -ag linter_filetypes

		while IFS='=' read -r key value; do
			if [[ $key == "filetype" ]]; then
				value=$(echo "$value" | jq -r '.[]')
				while IFS= read -r filetype; do
					linter_filetypes+=("$filetype")
				done <<<"$value"
				continue
			fi
			value=$(echo "$value" | tr -d "'" | tr -d '"')
			linter["$key"]=$value
		done < <(echo "$line" | jq -r 'to_entries|map("\(.key)=\(.value|tojson)")|.[]')

		linter[logfile]="/opt/goat/log/${linter[name]}.log"

		if [[ -v VALIDATE_PYTHON_MYPY && "${VALIDATE_PYTHON_MYPY,,}" == "false" ]] && [[ "${linter[name]}" == "mypy" ]]; then
			echo "mypy linter has been disabled"
			continue
		fi

		echo "===============================" >>"${linter[logfile]}"
		echo "Running linter: ${linter[name]}"
		echo "${linter[name]^^}" >>"${linter[logfile]}"

		lint_files &

		pid=$!
		pids["$pid"]="${linter[name]}"

		echo "-------------------------------" >>"${linter[logfile]}"
	done < <(jq -c '.[]' $input)

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

	echo -e "\nScanned ${#included[@]} files"
	echo -e "Excluded ${#excluded[@]} files\n"
}

setup_environment
check_environment
seiso_lint

for success in "${linter_successes[@]}"; do
	feedback INFO "$success completed successfully"
done

if [ -n "${linter_failures[*]}" ]; then
	for failure in "${linter_failures[@]}"; do
		feedback ERROR "$failure found errors"
	done
	feedback ERROR "Linting failed"
	exit 1
fi

feedback INFO "Linters found no errors."
