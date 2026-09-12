#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR

# shellcheck source=../../../lib/comm_util_funcs.sh
. "${SCRIPT_DIR}/../../../lib/comm_util_funcs.sh"

expect_classification() {
    local _expected="$1"
    local _status="$2"
    local _added="$3"
    local _defaults="$4"
    local _actual

    _actual="$(classify_ufw_state \
        "${_status}" "${_added}" "${_defaults}")"
    if [ "${_actual}" != "${_expected}" ]; then
        echo "FAILED: expected UFW classification '${_expected}'," >&2
        echo "    got '${_actual}' instead!" >&2
        exit 1
    fi
}

expect_classification "${UFW_KNOWN_BASELINE}" \
    "${_UFW_BASELINE_STATUS_CONTENTS}" \
    "${_UFW_BASELINE_ADDED_CONTENTS}" \
    "${_UFW_EXPECTED_DEFAULTS_CONTENTS}"

expect_classification "${UFW_INSTALLED_FRESH}" \
    "${_UFW_FRESH_STATUS_CONTENTS}" \
    "${_UFW_FRESH_ADDED_CONTENTS}" \
    "${_UFW_EXPECTED_DEFAULTS_CONTENTS}"

expect_classification "${UFW_CUSTOM_STATE}" \
    $'Status: active\nAn intentionally custom rule' \
    "${_UFW_BASELINE_ADDED_CONTENTS}" \
    "${_UFW_EXPECTED_DEFAULTS_CONTENTS}"

expect_classification "${UFW_CUSTOM_STATE}" \
    "${_UFW_BASELINE_STATUS_CONTENTS}" \
    $'Added user rules (see '\''ufw status'\'' for running firewall):\nufw allow 22/tcp\nufw allow 443/tcp' \
    "${_UFW_EXPECTED_DEFAULTS_CONTENTS}"

expect_classification "${UFW_UNK_STATE}" \
    "Status: disabled" \
    "${_UFW_FRESH_ADDED_CONTENTS}" \
    "${_UFW_EXPECTED_DEFAULTS_CONTENTS}"

expect_classification "${UFW_UNK_STATE}" \
    "${_UFW_FRESH_STATUS_CONTENTS}" \
    "${_UFW_FRESH_ADDED_CONTENTS}" \
    $'IPV6=yes\nDEFAULT_INPUT_POLICY="DROP"'

echo "PASSED shared UFW classifier state-matrix tests!"
