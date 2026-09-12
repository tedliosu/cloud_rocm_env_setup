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
    "${REPO_ROOT}/setup/azure/bin/azure_env_setup.sh" \
    "${REPO_ROOT}/setup/hot_aisle/bin/hot_aisle_env_setup.sh"; do
    _script_name="$(basename "${_setup_script}")"
    _unknown_output="${TEST_TMP_DIR}/${_script_name}.unknown-output"

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
done

echo "PASSED provider setup CLI tests!"
