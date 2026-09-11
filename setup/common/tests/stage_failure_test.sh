#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
MILESTONES_DIR="${TEST_TMP_DIR}/milestones"
readonly MILESTONES_DIR
FAILED_STAGE_RAN="${TEST_TMP_DIR}/failed-stage-ran"
readonly FAILED_STAGE_RAN
LATER_STAGE_RAN="${TEST_TMP_DIR}/later-stage-ran"
readonly LATER_STAGE_RAN
STAGE_OUTPUT="${TEST_TMP_DIR}/stage-output"
readonly STAGE_OUTPUT

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${MILESTONES_DIR}"

# util_funcs.sh resolves its global helper relative to a setup entry point's
# working directory, so reproduce that sourcing layout from this test directory.
cd "${SCRIPT_DIR}"
# shellcheck source=../lib/util_funcs.sh
. "../lib/util_funcs.sh"

failed_stage() {
    touch "${FAILED_STAGE_RAN}"
    return 23
}

later_stage() {
    touch "${LATER_STAGE_RAN}"
}

set +e
(
    set -e
    run_stage "${MILESTONES_DIR}" failed_stage
    run_stage "${MILESTONES_DIR}" later_stage
) >"${STAGE_OUTPUT}" 2>&1
stage_sequence_status="$?"
set -e

if [ "${stage_sequence_status}" -eq 0 ]; then
    echo "FAILED: a failed stage sequence returned success!" >&2
    exit 1
fi
if [ ! -f "${FAILED_STAGE_RAN}" ]; then
    echo "FAILED: the failure fixture did not run!" >&2
    exit 1
fi
if [ -e "${MILESTONES_DIR}/failed_stage.done" ]; then
    echo "FAILED: a failed stage acquired a completion marker!" >&2
    exit 1
fi
if [ -e "${LATER_STAGE_RAN}" ]; then
    echo "FAILED: a later stage ran after an earlier stage failed!" >&2
    exit 1
fi
if [ -e "${MILESTONES_DIR}/later_stage.done" ]; then
    echo "FAILED: a later stage acquired a completion marker without running!" >&2
    exit 1
fi

echo "PASSED shared stage failure-propagation test!"
