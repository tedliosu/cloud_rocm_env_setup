#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
REBOOT_CALLS="${TEST_TMP_DIR}/reboot-calls"
readonly REBOOT_CALLS
SEQUENCE_OUTPUT="${TEST_TMP_DIR}/sequence-output"
readonly SEQUENCE_OUTPUT
BOOT_ID_A="11111111-1111-4111-8111-111111111111"
readonly BOOT_ID_A
BOOT_ID_B="22222222-2222-4222-8222-222222222222"
readonly BOOT_ID_B
TEST_BOOT_ID="${BOOT_ID_A}"
TEST_REBOOT_STATUS=0
SEQUENCE_STATUS=0

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

# util_funcs.sh resolves its global helper relative to a setup entry point's
# working directory, so reproduce that sourcing layout from this test directory.
cd "${SCRIPT_DIR}"
# shellcheck source=../lib/util_funcs.sh
. "../lib/util_funcs.sh"

_read_linux_boot_id() {
    printf "%s\n" "${TEST_BOOT_ID}"
}

sudo() {
    if [ "$#" -ne 2 ] || [ "$1" != "--set-home" ] || [ "$2" != "reboot" ]; then
        return 64
    fi
    printf "reboot\n" >> "${REBOOT_CALLS}"
    return "${TEST_REBOOT_STATUS}"
}

run_reboot_sequence() {
    local _milestones_dir="$1"
    local _phase_name="$2"
    local _later_stage_marker="$3"

    set +e
    (
        set -e
        reboot_with_ack_dont_wrap "${_milestones_dir}" "${_phase_name}"
        touch "${_later_stage_marker}"
    ) >"${SEQUENCE_OUTPUT}" 2>&1
    SEQUENCE_STATUS="$?"
    set -e
}

assert_no_done_marker() {
    local _milestones_dir="$1"
    local _phase_name="$2"

    if [ -e "${_milestones_dir}/${_phase_name}.done" ]; then
        echo "FAILED: unacknowledged reboot phase '${_phase_name}' is complete!" >&2
        exit 1
    fi
}

SUCCESS_DIR="${TEST_TMP_DIR}/successful-command"
SUCCESS_LATER_STAGE="${TEST_TMP_DIR}/successful-command-later-stage"
mkdir "${SUCCESS_DIR}"

run_reboot_sequence "${SUCCESS_DIR}" system_upgrade "${SUCCESS_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -ne 0 ]; then
    echo "FAILED: successful reboot request returned failure!" >&2
    exit 1
fi
if [ -e "${SUCCESS_LATER_STAGE}" ]; then
    echo "FAILED: a later stage ran before reboot acknowledgement!" >&2
    exit 1
fi
if [ "$(cat "${SUCCESS_DIR}/system_upgrade.pending")" != "${BOOT_ID_A}" ]; then
    echo "FAILED: pending reboot state did not record the current boot ID!" >&2
    exit 1
fi
assert_no_done_marker "${SUCCESS_DIR}" system_upgrade

run_reboot_sequence "${SUCCESS_DIR}" system_upgrade "${SUCCESS_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -eq 0 ]; then
    echo "FAILED: same-boot rerun did not report a pending reboot!" >&2
    exit 1
fi
if [ -e "${SUCCESS_LATER_STAGE}" ]; then
    echo "FAILED: a later stage ran on a same-boot rerun!" >&2
    exit 1
fi
assert_no_done_marker "${SUCCESS_DIR}" system_upgrade

TEST_BOOT_ID="${BOOT_ID_B}"
run_reboot_sequence "${SUCCESS_DIR}" system_upgrade "${SUCCESS_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -ne 0 ]; then
    echo "FAILED: changed boot ID did not acknowledge the reboot!" >&2
    exit 1
fi
if [ ! -f "${SUCCESS_DIR}/system_upgrade.done" ] ||
    [ -e "${SUCCESS_DIR}/system_upgrade.pending" ]; then
    echo "FAILED: acknowledged reboot state was not completed atomically!" >&2
    exit 1
fi
if [ ! -f "${SUCCESS_LATER_STAGE}" ]; then
    echo "FAILED: a later stage did not run after reboot acknowledgement!" >&2
    exit 1
fi

FAILED_DIR="${TEST_TMP_DIR}/failed-command"
FAILED_LATER_STAGE="${TEST_TMP_DIR}/failed-command-later-stage"
mkdir "${FAILED_DIR}"
TEST_BOOT_ID="${BOOT_ID_A}"
TEST_REBOOT_STATUS=42
run_reboot_sequence "${FAILED_DIR}" driver_install "${FAILED_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -eq 0 ]; then
    echo "FAILED: failed reboot command returned success!" >&2
    exit 1
fi
if [ -e "${FAILED_LATER_STAGE}" ]; then
    echo "FAILED: a later stage ran after the reboot command failed!" >&2
    exit 1
fi
if [ "$(cat "${FAILED_DIR}/driver_install.pending")" != "${BOOT_ID_A}" ]; then
    echo "FAILED: failed reboot command did not preserve pending state!" >&2
    exit 1
fi
assert_no_done_marker "${FAILED_DIR}" driver_install

MALFORMED_DIR="${TEST_TMP_DIR}/malformed-state"
MALFORMED_LATER_STAGE="${TEST_TMP_DIR}/malformed-state-later-stage"
mkdir "${MALFORMED_DIR}"
printf "not-a-boot-id\n" > "${MALFORMED_DIR}/system_upgrade.pending"
TEST_REBOOT_STATUS=0
run_reboot_sequence "${MALFORMED_DIR}" system_upgrade "${MALFORMED_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -eq 0 ]; then
    echo "FAILED: malformed pending reboot state was accepted!" >&2
    exit 1
fi
if [ -e "${MALFORMED_LATER_STAGE}" ]; then
    echo "FAILED: a later stage ran after malformed reboot state!" >&2
    exit 1
fi
assert_no_done_marker "${MALFORMED_DIR}" system_upgrade

LEGACY_DIR="${TEST_TMP_DIR}/legacy-completed-state"
LEGACY_LATER_STAGE="${TEST_TMP_DIR}/legacy-later-stage"
mkdir "${LEGACY_DIR}"
touch "${LEGACY_DIR}/reboot_once_dont_wrap.done"
set +e
(
    set -e
    reboot_once_dont_wrap "${LEGACY_DIR}"
    touch "${LEGACY_LATER_STAGE}"
) >"${SEQUENCE_OUTPUT}" 2>&1
SEQUENCE_STATUS="$?"
set -e
if [ "${SEQUENCE_STATUS}" -ne 0 ] || [ ! -f "${LEGACY_LATER_STAGE}" ]; then
    echo "FAILED: established single-reboot completion marker was not preserved!" >&2
    exit 1
fi

if [ "$(wc --lines < "${REBOOT_CALLS}")" -ne 2 ]; then
    echo "FAILED: unexpected number of reboot command invocations!" >&2
    exit 1
fi

echo "PASSED shared reboot acknowledgement tests!"
