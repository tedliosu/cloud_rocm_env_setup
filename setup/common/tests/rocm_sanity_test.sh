#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
ROCMINFO_FAILURE_OUTPUT="${TEST_TMP_DIR}/rocminfo-failure-output"
readonly ROCMINFO_FAILURE_OUTPUT
DRIVER_UNLOADED_OUTPUT="${TEST_TMP_DIR}/driver-unloaded-output"
readonly DRIVER_UNLOADED_OUTPUT
HEALTHY_OUTPUT="${TEST_TMP_DIR}/healthy-output"
readonly HEALTHY_OUTPUT
HIPCONFIG_CALLED_MARKER="${TEST_TMP_DIR}/hipconfig-called"
readonly HIPCONFIG_CALLED_MARKER
TEST_ROCMINFO_MODE=""
SCENARIO_STATUS=0

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

# util_funcs.sh resolves its global helper relative to a setup entry point's
# working directory, so reproduce that sourcing layout from this test directory.
cd "${SCRIPT_DIR}"
# shellcheck source=../lib/util_funcs.sh
. "../lib/util_funcs.sh"

rocminfo() {
    case ${TEST_ROCMINFO_MODE} in
        command_failure)
            printf 'ROCk module is NOT loaded\n'
            return 23
            ;;
        driver_unloaded)
            printf 'ROCk module is NOT loaded\n'
            ;;
        healthy)
            printf 'Name: gfx942\n'
            ;;
        *)
            return 64
            ;;
    esac
}

hipconfig() {
    [ "$#" -eq 1 ] && [ "$1" = "--rocmpath" ] || return 64
    touch "${HIPCONFIG_CALLED_MARKER}"
    printf '/opt/rocm-7.2.4\n'
}

run_scenario() {
    local _output_file="$1"

    rm --force "${HIPCONFIG_CALLED_MARKER}"
    set +e
    (
        set -e
        ensure_rocm_env_sanity_dont_wrap 7.2 '^7\.2\.[0-9]+'
    ) >"${_output_file}" 2>&1
    SCENARIO_STATUS="$?"
    set -e
}

TEST_ROCMINFO_MODE="command_failure"
run_scenario "${ROCMINFO_FAILURE_OUTPUT}"
if [ "${SCENARIO_STATUS}" -eq 0 ]; then
    echo "FAILED: unsuccessful rocminfo execution was accepted!" >&2
    exit 1
fi
if ! grep --fixed-strings --quiet \
    "'rocminfo' exited with status 23" "${ROCMINFO_FAILURE_OUTPUT}"; then
    echo "FAILED: rocminfo execution failure was not diagnosed separately!" >&2
    exit 1
fi
if grep --fixed-strings --quiet \
    "amdgpu dkms not detected" "${ROCMINFO_FAILURE_OUTPUT}"; then
    echo "FAILED: rocminfo execution failure was mistaken for probe output!" >&2
    exit 1
fi
if [ -e "${HIPCONFIG_CALLED_MARKER}" ]; then
    echo "FAILED: hipconfig ran after rocminfo execution failed!" >&2
    exit 1
fi

TEST_ROCMINFO_MODE="driver_unloaded"
run_scenario "${DRIVER_UNLOADED_OUTPUT}"
if [ "${SCENARIO_STATUS}" -eq 0 ]; then
    echo "FAILED: successful rocminfo probe reported an unloaded driver but passed!" >&2
    exit 1
fi
if ! grep --fixed-strings --quiet \
    "amdgpu dkms not detected" "${DRIVER_UNLOADED_OUTPUT}"; then
    echo "FAILED: unloaded AMDGPU driver was not diagnosed!" >&2
    exit 1
fi
if [ -e "${HIPCONFIG_CALLED_MARKER}" ]; then
    echo "FAILED: hipconfig ran after rocminfo reported an unloaded driver!" >&2
    exit 1
fi

TEST_ROCMINFO_MODE="healthy"
run_scenario "${HEALTHY_OUTPUT}"
if [ "${SCENARIO_STATUS}" -ne 0 ]; then
    echo "FAILED: healthy ROCm sanity fixtures were rejected!" >&2
    exit 1
fi
if [ ! -f "${HIPCONFIG_CALLED_MARKER}" ]; then
    echo "FAILED: healthy rocminfo result did not reach hipconfig!" >&2
    exit 1
fi

echo "PASSED ROCm environment sanity tests!"
