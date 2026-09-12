#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
USERMOD_CALLS="${TEST_TMP_DIR}/usermod-calls"
readonly USERMOD_CALLS
SEQUENCE_OUTPUT="${TEST_TMP_DIR}/sequence-output"
readonly SEQUENCE_OUTPUT
TEST_USERNAME="azureuser"
readonly TEST_USERNAME
TEST_CONFIGURED_GROUPS="${TEST_USERNAME}"
TEST_EFFECTIVE_GROUPS="${TEST_USERNAME}"
TEST_USERMOD_STATUS=0
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

logname() {
    printf "%s\n" "${TEST_USERNAME}"
}

id() {
    if [ "$#" -eq 2 ] && [ "$1" = "--user" ] && [ "$2" = "--name" ]; then
        printf "%s\n" "${TEST_USERNAME}"
    elif [ "$#" -eq 3 ] && [ "$1" = "--name" ] && [ "$2" = "--groups" ] &&
        [ "$3" = "${TEST_USERNAME}" ]; then
        printf "%s\n" "${TEST_CONFIGURED_GROUPS}"
    elif [ "$#" -eq 2 ] && [ "$1" = "--name" ] && [ "$2" = "--groups" ]; then
        printf "%s\n" "${TEST_EFFECTIVE_GROUPS}"
    else
        return 64
    fi
}

sudo() {
    if [ "$#" -ne 6 ] || [ "$1" != "--set-home" ] ||
        [ "$2" != "usermod" ] || [ "$3" != "--append" ] ||
        [ "$4" != "--groups" ] || [ "$5" != "video,render" ] ||
        [ "$6" != "${TEST_USERNAME}" ]; then
        return 64
    fi
    printf "%s\n" "$*" >> "${USERMOD_CALLS}"
    if [ "${TEST_USERMOD_STATUS}" -eq 0 ]; then
        TEST_CONFIGURED_GROUPS="${TEST_USERNAME} video render"
    fi
    return "${TEST_USERMOD_STATUS}"
}

run_group_sequence() {
    local _later_stage_marker="$1"

    set +e
    (
        set -e
        ensure_groups_maybe_require_relogin_dont_wrap
        touch "${_later_stage_marker}"
    ) >"${SEQUENCE_OUTPUT}" 2>&1
    SEQUENCE_STATUS="$?"
    set -e
}

MUTATION_LATER_STAGE="${TEST_TMP_DIR}/mutation-later-stage"
run_group_sequence "${MUTATION_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -ne 0 ]; then
    echo "FAILED: successful group mutation returned failure!" >&2
    exit 1
fi
if [ -e "${MUTATION_LATER_STAGE}" ]; then
    echo "FAILED: setup continued before a fresh login!" >&2
    exit 1
fi
if [ "$(wc --lines < "${USERMOD_CALLS}")" -ne 1 ]; then
    echo "FAILED: expected exactly one group-mutation command!" >&2
    exit 1
fi

TEST_CONFIGURED_GROUPS="${TEST_USERNAME} video render"
STALE_LATER_STAGE="${TEST_TMP_DIR}/stale-login-later-stage"
run_group_sequence "${STALE_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -eq 0 ]; then
    echo "FAILED: stale login without effective GPU groups was accepted!" >&2
    exit 1
fi
if [ -e "${STALE_LATER_STAGE}" ]; then
    echo "FAILED: setup continued from a stale login!" >&2
    exit 1
fi

TEST_EFFECTIVE_GROUPS="${TEST_USERNAME} video render"
FRESH_LATER_STAGE="${TEST_TMP_DIR}/fresh-login-later-stage"
run_group_sequence "${FRESH_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -ne 0 ] || [ ! -f "${FRESH_LATER_STAGE}" ]; then
    echo "FAILED: fresh login with effective GPU groups was rejected!" >&2
    exit 1
fi
if [ "$(wc --lines < "${USERMOD_CALLS}")" -ne 1 ]; then
    echo "FAILED: configured GPU groups were mutated again!" >&2
    exit 1
fi

TEST_CONFIGURED_GROUPS="${TEST_USERNAME}"
TEST_EFFECTIVE_GROUPS="${TEST_USERNAME}"
TEST_USERMOD_STATUS=42
FAILED_LATER_STAGE="${TEST_TMP_DIR}/failed-usermod-later-stage"
run_group_sequence "${FAILED_LATER_STAGE}"
if [ "${SEQUENCE_STATUS}" -eq 0 ]; then
    echo "FAILED: failed group mutation returned success!" >&2
    exit 1
fi
if [ -e "${FAILED_LATER_STAGE}" ]; then
    echo "FAILED: setup continued after group mutation failed!" >&2
    exit 1
fi
if [ "$(wc --lines < "${USERMOD_CALLS}")" -ne 2 ]; then
    echo "FAILED: failed group mutation was not invoked exactly once!" >&2
    exit 1
fi

echo "PASSED shared GPU-group relogin tests!"
