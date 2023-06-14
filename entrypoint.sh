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

	# Set default value for autofix
	export AUTO_FIX="true"

	# Create variables for the various dictionary file paths
	export GLOBAL_DICTIONARY="/etc/opt/goat/seiso_global_dictionary.txt"
	export REPO_DICTIONARY="${GITHUB_WORKSPACE:-/goat}/.github/etc/dictionary.txt"

	if [[ ${INPUT_DISABLE_MYPY:-} == "true" ]]; then
		export VALIDATE_PYTHON_MYPY="false"
	fi

	if [[ -n ${INPUT_EXCLUDE:+x} ]]; then
		export FILTER_REGEX_EXCLUDE="${INPUT_EXCLUDE}"
	fi
	
	if [[ ${INPUT_AUTO_FIX:-true} == "false" ]]; then
		# Let INPUT_AUTO_FIX override the autofix value. This allows for disabling autofix locally.
		AUTO_FIX="false"
	fi

	if [[ ${INPUT_LOG_LEVEL:='VERBOSE'} =~ ^(ERROR|WARN|NOTICE|VERBOSE|DEBUG|TRACE)$ ]]; then
		export LOG_LEVEL="${INPUT_LOG_LEVEL}"
		export ACTIONS_RUNNER_DEBUG="true"
	fi

	declare -a linter_failures
	declare -a linter_successes
	declare -a linter_autofix
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

	if [[ ${CI:-false} == "true" || ${CONTINUOUS_INTEGRATION:-false} == "true" || ${GITHUB_ACTIONS:-false} == "true" ]]; then
		export IS_PIPELINE="true"
		# If this is run in a pipeline and INPUT_AUTO_FIX does not equal true, disable autofix. INPUT_AUTO_FIX="true" would force autofix
		# in the pipeline and result in dirty git directory if anything was fixed.
		if [[ ${INPUT_AUTO_FIX:-true} != "true" ]]; then
			AUTO_FIX="false"
		fi
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

function lint_files() {
	# Turn the received string back into an object
	local -n linter_array="$1"
	local filetypes_to_lint=("${@:2}")
	local linter_args="${linter_array[args]}"
	local files_to_lint=""
	local env_var_name="${linter_array[env]}"

	if [[ -v "${env_var_name}" ]]; then
		linter_args="${!env_var_name}"
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
			excluded+=("${file}")
			continue
		fi
		included+=("${file}")
	done < <(find . \( -path "./.git" -prune \) -o \( -type f -print \))

	declare -A pids

	input="/etc/opt/goat/linters.json"

	while read -r line; do
		unset linter
		declare -A linter
		unset linter_filetypes
		declare -a linter_filetypes

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

		if [[ -v linter[autofix] && -n "${linter[autofix]}" ]]; then
			if [[ ${AUTO_FIX:-true} == "true" ]]; then
				# Replacing the linter's args with the autofix args for that linter
				linter[args]="${linter[autofix]}"
			fi

			linter_autofix+=("${linter[name]}")
		fi

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
}

start=$(date +%s)
setup_environment
check_environment
seiso_lint
end=$(date +%s)
runtime=$((end - start))

echo -e "\nScanned ${#included[@]} files in ${runtime} seconds"
echo -e "Excluded ${#excluded[@]} files\n"

linting_failed="false"

if [ -n "${linter_successes[*]}" ]; then
	if [[ -n "${linter_autofix[*]}" && -n $(git status -s) && ${AUTO_FIX:-true} == "true" ]]; then
		for fix in "${linter_autofix[@]}"; do
			cat "/opt/goat/log/$fix.log"
		done
		if [[ ${IS_PIPELINE:-false} == "true" ]]; then
			feedback ERROR "Linting found errors that can be fixed automatically when run locally"
			linting_failed="true"
		else
			feedback INFO "Some errors were autofixed"
		fi
	fi

	for success in "${linter_successes[@]}"; do
		feedback INFO "$success completed successfully"
	done
fi

if [ -n "${linter_failures[*]}" ]; then	
	for failure in "${linter_failures[@]}"; do
		cannot_autofix="false"

		for element in "${linter_autofix[@]}"; do
			if [ "$element" == "$failure" ]; then
				feedback ERROR "$element can perform autofix on some errors when run locally"
				cannot_autofix="true"
			fi
		done
		
		if [ "$cannot_autofix" == "false" ]; then
			feedback ERROR "$failure found errors"
		fi
	done

	feedback ERROR "Linting failed"
	linting_failed="true"
fi

if [[ $linting_failed == "true" ]]; then
	exit 1
fi

feedback INFO "Linters found no errors."