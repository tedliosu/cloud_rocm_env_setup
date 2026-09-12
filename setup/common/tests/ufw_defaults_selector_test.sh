#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
UFW_DEFAULTS_FIXTURE="${TEST_TMP_DIR}/ufw-defaults"
readonly UFW_DEFAULTS_FIXTURE

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

# shellcheck source=../../../lib/comm_util_funcs.sh
. "${SCRIPT_DIR}/../../../lib/comm_util_funcs.sh"

printf '%s\n' \
    '# /etc/default/ufw fixture' \
    'IPV6=yes' \
    'DEFAULT_INPUT_POLICY="DROP"' \
    'DEFAULT_OUTPUT_POLICY="ACCEPT"' \
    'DEFAULT_FORWARD_POLICY="DROP"' \
    'DEFAULT_APPLICATION_POLICY="SKIP"' \
    'DEFAULT_UNRELATED_POLICY="ACCEPT"' \
    'IPV6_EXTRA=yes' \
    > "${UFW_DEFAULTS_FIXTURE}"

_selected_defaults="$(grep --extended-regexp \
    "${UFW_DEFAULTS_SELECTOR_REGEX}" "${UFW_DEFAULTS_FIXTURE}")"
if [ "${_selected_defaults}" != "${_UFW_EXPECTED_DEFAULTS_CONTENTS}" ]; then
    echo "FAILED: shared UFW defaults selector did not select exactly the" >&2
    echo "    expected five keys!" >&2
    exit 1
fi

echo "PASSED shared UFW defaults selector test!"
