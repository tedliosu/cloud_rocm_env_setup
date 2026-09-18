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
DELETE_ARGUMENTS="${TEST_TMP_DIR}/delete-arguments"
readonly DELETE_ARGUMENTS

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

rm --force "${GUARD_OUTPUT}"
set +e
(
    rm() {
        touch "${DELETE_CALLED_MARKER}"
    }
    guarded_rm_rf "${PERMITTED_ROOT_DIR}"
) >"${GUARD_OUTPUT}" 2>&1
guard_status="$?"
set -e
if [ "${guard_status}" -eq 0 ] || [ -e "${DELETE_CALLED_MARKER}" ]; then
    echo "FAILED: deletion guard accepted the permitted root itself!" >&2
    exit 1
fi

set +e
(
    rm() {
        touch "${DELETE_CALLED_MARKER}"
    }
    guarded_rm_rf "/tmp/outside-permitted-root"
) >"${GUARD_OUTPUT}" 2>&1
guard_status="$?"
set -e
if [ "${guard_status}" -eq 0 ] || [ -e "${DELETE_CALLED_MARKER}" ]; then
    echo "FAILED: deletion guard accepted an outside path!" >&2
    exit 1
fi

(
    _permitted_root_dir="preserve-permitted-root-sentinel"
    _curr_username="preserve-username-sentinel"
    _target_path="preserve-target-sentinel"
    _canonical_target_path="preserve-canonical-sentinel"
    rm() {
        printf '%s\n' "$@" > "${DELETE_ARGUMENTS}"
    }
    guarded_rm_rf \
        "${PERMITTED_ROOT_DIR}/first deletion fixture" \
        "${PERMITTED_ROOT_DIR}/second[fixture]"
    if [ "${_permitted_root_dir}" != "preserve-permitted-root-sentinel" ] ||
        [ "${_curr_username}" != "preserve-username-sentinel" ] ||
        [ "${_target_path}" != "preserve-target-sentinel" ] ||
        [ "${_canonical_target_path}" != "preserve-canonical-sentinel" ]; then
        echo "FAILED: guarded deletion leaked helper state into its caller!" >&2
        exit 1
    fi
)
if [ "$(<"${DELETE_ARGUMENTS}")" != "$(printf '%s\n' \
    '--recursive' '--force' \
    "${PERMITTED_ROOT_DIR}/first deletion fixture" \
    "${PERMITTED_ROOT_DIR}/second[fixture]")" ]; then
    echo "FAILED: guarded deletion did not preserve multiple path arguments!" >&2
    exit 1
fi
echo "PASSED guarded recursive-deletion boundary tests!"
