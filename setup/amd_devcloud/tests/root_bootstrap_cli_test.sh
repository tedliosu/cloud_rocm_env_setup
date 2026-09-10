#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROOT_BOOTSTRAP="$(realpath \
    "${SCRIPT_DIR}/../bin/amd_devcloud_root_bootstrap.sh")"
TEST_TMP_DIR="$(mktemp --directory)"
TEST_KEY_FILE="${TEST_TMP_DIR}/authorized_keys"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

touch "${TEST_KEY_FILE}"

"${ROOT_BOOTSTRAP}" --help >/dev/null

if "${ROOT_BOOTSTRAP}" >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted missing required arguments!" >&2
    exit 1
fi
if "${ROOT_BOOTSTRAP}" --unknown-option >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted an unknown option!" >&2
    exit 1
fi
if "${ROOT_BOOTSTRAP}" --target-user devcloud --target-user devcloud2 \
    --authorized-key-file "${TEST_KEY_FILE}" >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted a repeated target-user option!" >&2
    exit 1
fi
if "${ROOT_BOOTSTRAP}" --target-user devcloud \
    --authorized-key-file "${TEST_KEY_FILE}" \
    --authorized-key-file "${TEST_KEY_FILE}" >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted a repeated key-file option!" >&2
    exit 1
fi

for _invalid_username in root _devcloud devcloud_ devcloud- DevCloud \
    'dev.cloud' 'dev cloud' $'devcloud\nother' \
    'abcdefghijklmnopqrstuvwxyzabcdefg'; do
    if "${ROOT_BOOTSTRAP}" --target-user "${_invalid_username}" \
        --authorized-key-file "${TEST_KEY_FILE}" >/dev/null 2>&1; then
        echo "FAILED: root bootstrap accepted invalid username" \
            "'${_invalid_username}'!" >&2
        exit 1
    fi
done

if [ "${EUID}" -ne 0 ]; then
    for _valid_username in a devcloud dev-cloud_2; do
        _error_output="$("${ROOT_BOOTSTRAP}" --target-user "${_valid_username}" \
            --authorized-key-file "${TEST_KEY_FILE}" 2>&1 || :)"
        if ! grep --fixed-strings --quiet \
            "AMD DevCloud root bootstrap must run as root" <<< "${_error_output}"; then
            echo "FAILED: valid username '${_valid_username}' did not reach" >&2
            echo "    the non-root invocation guard!" >&2
            exit 1
        fi
    done
fi

echo "PASSED AMD DevCloud root-bootstrap CLI tests!"
