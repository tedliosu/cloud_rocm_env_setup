#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
readonly REPO_ROOT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
DELETE_CALLED_MARKER="${TEST_TMP_DIR}/delete-called"
readonly DELETE_CALLED_MARKER
GUARD_OUTPUT="${TEST_TMP_DIR}/guard-output"
readonly GUARD_OUTPUT

# shellcheck source=../../../lib/comm_util_funcs.sh
. "${REPO_ROOT}/lib/comm_util_funcs.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

if [ "$(id --user --name)" = "root" ]; then
    PERMITTED_ROOT_DIR="/root"
else
    PERMITTED_ROOT_DIR="/home/$(id --user --name)"
fi
readonly PERMITTED_ROOT_DIR

set +e
(
    realpath() {
        return 23
    }
    rm() {
        touch "${DELETE_CALLED_MARKER}"
    }

    guarded_rm_rf "${PERMITTED_ROOT_DIR}/resolution-failure-fixture"
) >"${GUARD_OUTPUT}" 2>&1
guard_status="$?"
set -e

if [ "${guard_status}" -eq 0 ]; then
    echo "FAILED: path-resolution failure returned success!" >&2
    exit 1
fi
if [ -e "${DELETE_CALLED_MARKER}" ]; then
    echo "FAILED: deletion ran after path resolution failed!" >&2
    exit 1
fi

echo "PASSED guarded recursive-deletion resolution-failure test!"
