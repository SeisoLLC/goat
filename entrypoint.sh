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

	# Map certain environment variables
	if [[ ${INPUT_DISABLE_TERRASCAN-} == "true" ]]; then
		export VALIDATE_TERRAFORM_TERRASCAN="false"
	fi

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

	linter_failed="false"
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
	local file="$1"

	if grep -q -v 'kustomize.config.k8s.io' "${file}" &&
		grep -q -v "tekton" "${file}" &&
		grep -q -E '(apiVersion):' "${file}" &&
		grep -q -E '(kind):' "${file}"; then
		return 0
	fi

	return 1
}

function detect_cloudformation_file() {
	local file="$1"

	if grep -q 'AWSTemplateFormatVersion' "${file}" >/dev/null; then
		return 0
	fi

	if grep -q -E '(AWS|Alexa|Custom)::' "${file}" >/dev/null; then
		return 0
	fi

	return 1
}

function get_files_matching_filetype() {
	local filenames=("$@")
	matching_files=()

	for file in "${filenames[@]}"; do
		filename=$(basename "$file")

		for filetype in "${linter_filetypes[@]}"; do
			if [[ $filename == *"$filetype" ]]; then
				if [ "${linter[name]}" == "cfn-lint" ]; then
					if ! detect_cloudformation_file "${file}"; then
						break
					fi
				fi
				if [ "${linter[name]}" == "kubeconform" ]; then
					if ! detect_kubernetes_file "${file}"; then
						break
					fi
				fi
				matching_files+=("$file")
				break
			fi
		done
	done

	echo "${matching_files[@]}"
}

function lint_files() {
	local linter_args="${linter[args]}"

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

	for file in $(get_files_matching_filetype "${included[@]}"); do
		if [[ "${linter[executor]+x}" ]]; then
			cmd="${linter[executor]} ${linter[name]} $linter_args ${file}"
		else
			cmd="${linter[name]} $linter_args ${file}"
		fi

		eval "$cmd" >>"${linter[logfile]}" 2>&1
	done
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
		included+=("$file")
	done < <(find . \( -path "./.git" -prune \) -o \( -type f -print \))

	declare -gA pids

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
			linter_failed="true"
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

if [ "${linter_failed:-true}" == "true" ]; then
	for failure in "${linter_failures[@]}"; do
		feedback ERROR "$failure found errors"
	done
	feedback ERROR "Linting failed"
	exit 1
fi

feedback INFO "Linters found no errors."
