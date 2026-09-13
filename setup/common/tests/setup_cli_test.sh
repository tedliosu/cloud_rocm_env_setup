#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
readonly REPO_ROOT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

for _setup_script in \
    "${REPO_ROOT}/setup/amd_devcloud/bin/amd_devcloud_env_setup.sh" \
    "${REPO_ROOT}/setup/azure/bin/azure_env_setup.sh" \
    "${REPO_ROOT}/setup/hot_aisle/bin/hot_aisle_env_setup.sh"; do
    _script_name="$(basename "${_setup_script}")"
    _unknown_output="${TEST_TMP_DIR}/${_script_name}.unknown-output"
    _provider_dir="$(realpath "$(dirname "${_setup_script}")/..")"
    _state_tracker_path="${_provider_dir}/state_trackers"
    _logs_path="${_provider_dir}/logs"
    _state_tracker_was_absent=0
    _logs_was_absent=0

    if [ ! -e "${_state_tracker_path}" ] && [ ! -L "${_state_tracker_path}" ]; then
        _state_tracker_was_absent=1
    fi
    if [ ! -e "${_logs_path}" ] && [ ! -L "${_logs_path}" ]; then
        _logs_was_absent=1
    fi

    "${_setup_script}" --help >/dev/null

    if "${_setup_script}" --unknown-option >"${_unknown_output}" 2>&1; then
        echo "FAILED: ${_script_name} accepted an unknown option!" >&2
        exit 1
    fi
    if ! grep --fixed-strings --quiet \
        "ERROR: unknown argument '--unknown-option'!" "${_unknown_output}"; then
        echo "FAILED: ${_script_name} did not diagnose its unknown option!" >&2
        exit 1
    fi

    _plan_output="$("${_setup_script}" --show-plan-only)"
    while IFS= read -r _plan_line; do
        if [ -n "${_plan_line}" ] && [[ "${_plan_line}" != "[PLAN ONLY]"* ]]; then
            echo "FAILED: ${_script_name} emitted unlabeled plan output:" >&2
            echo "    ${_plan_line}" >&2
            exit 1
        fi
    done <<< "${_plan_output}"
    if { [ "${_state_tracker_was_absent}" -eq 1 ] &&
            { [ -e "${_state_tracker_path}" ] ||
                [ -L "${_state_tracker_path}" ]; }; } ||
        { [ "${_logs_was_absent}" -eq 1 ] &&
            { [ -e "${_logs_path}" ] || [ -L "${_logs_path}" ]; }; }; then
        echo "FAILED: ${_script_name} created local state during plan mode!" >&2
        exit 1
    fi
done

echo "PASSED provider setup CLI tests!"
