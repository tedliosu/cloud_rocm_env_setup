#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
BUILD_FAILURE_OUTPUT="${TEST_TMP_DIR}/build-failure-output"
readonly BUILD_FAILURE_OUTPUT
INSTALL_FAILURE_OUTPUT="${TEST_TMP_DIR}/install-failure-output"
readonly INSTALL_FAILURE_OUTPUT
INSTALL_CALLED_MARKER="${TEST_TMP_DIR}/install-called"
readonly INSTALL_CALLED_MARKER
CLEANUP_CALLED_MARKER="${TEST_TMP_DIR}/cleanup-called"
readonly CLEANUP_CALLED_MARKER
TEST_PIP_MODE=""
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

virtualenv() {
    mkdir --parents "$1/bin"
    printf '%s\n' 'deactivate() { :; }' > "$1/bin/activate"
}

git() {
    if [ "$#" -eq 3 ] && [ "$1" = "clone" ]; then
        mkdir --parents "$3/dist"
        touch "$3/dist/cupy-test.whl"
    fi
    return 0
}

hipconfig() {
    [ "$#" -eq 1 ] && [ "$1" = "--rocmpath" ] || return 64
    printf '/opt/rocm-7.2.0\n'
}

canonicalize_rocm_root() {
    [ "$#" -eq 1 ] && [ "$1" = "/opt/rocm-7.2.0" ] || return 64
    printf '/opt/rocm-7.2.0\n'
}

select_cupy_rocm_home() {
    [ "$#" -eq 2 ] && [ "$1" = "/opt/rocm-7.2.0" ] &&
        [ "$2" = "${CUPY_CONVENTIONAL_ROCM_HOME}" ] || return 64
    printf '%s\n' "${CUPY_CONVENTIONAL_ROCM_HOME}"
}

detect_amd_smi_gpu_arch() {
    printf 'gfx942\n'
}

guarded_rm_rf() {
    touch "${CLEANUP_CALLED_MARKER}"
}

pip() {
    local _log_path
    local _line_number

    if [ "$#" -ge 3 ] && [ "$1" = "--log" ] && [ "$3" = "wheel" ]; then
        _log_path="$2"
        if [ "${TEST_PIP_MODE}" = "build_failure" ]; then
            for ((_line_number = 1; _line_number <= 100; _line_number++)); do
                printf 'build-log-line-%s\n' "${_line_number}" >> "${_log_path}"
            done
            return 23
        fi
        printf 'successful build log\n' >> "${_log_path}"
        return 0
    fi
    if [ "$#" -eq 2 ] && [ "$1" = "install" ] &&
        [ "$2" = "${TEST_CUPY_DIR}/dist/cupy-test.whl" ]; then
        touch "${INSTALL_CALLED_MARKER}"
        if [ "${TEST_PIP_MODE}" = "install_failure" ]; then
            return 24
        fi
        return 0
    fi
    return 0
}

run_failure_scenario() {
    local _scenario_name="$1"
    local _output_file="$2"

    TEST_CUPY_DIR="${TEST_TMP_DIR}/${_scenario_name}-cupy"
    TEST_ENV_DIR="${TEST_TMP_DIR}/${_scenario_name}-env"
    TEST_BUILD_LOG="${TEST_TMP_DIR}/${_scenario_name}-build.log"
    export TEST_CUPY_DIR

    set +e
    (
        set -e
        ensure_gpu_arr_virtualenv "${TEST_ENV_DIR}" "${TEST_CUPY_DIR}" \
            /test/requirements.txt v-test "${TEST_BUILD_LOG}"
    ) >"${_output_file}" 2>&1
    SCENARIO_STATUS="$?"
    set -e
}

TEST_PIP_MODE="build_failure"
run_failure_scenario build "${BUILD_FAILURE_OUTPUT}"
if [ "${SCENARIO_STATUS}" -ne 23 ]; then
    echo "FAILED: CuPy wheel-build failure status was not preserved!" >&2
    exit 1
fi
if [ "$(grep --count '^build-log-line-' "${BUILD_FAILURE_OUTPUT}")" -ne 80 ]; then
    echo "FAILED: CuPy wheel-build failure did not print its bounded log tail!" >&2
    exit 1
fi
if [ -e "${INSTALL_CALLED_MARKER}" ] || [ -e "${CLEANUP_CALLED_MARKER}" ]; then
    echo "FAILED: build failure reached install or cleanup work!" >&2
    exit 1
fi

TEST_PIP_MODE="install_failure"
run_failure_scenario install "${INSTALL_FAILURE_OUTPUT}"
if [ "${SCENARIO_STATUS}" -ne 24 ]; then
    echo "FAILED: CuPy wheel-install failure status was not preserved!" >&2
    exit 1
fi
if ! grep --fixed-strings --quiet \
    "FAILED to install the built CuPy wheel!" "${INSTALL_FAILURE_OUTPUT}"; then
    echo "FAILED: CuPy wheel-install diagnostic was not emitted!" >&2
    exit 1
fi
if [ ! -f "${INSTALL_CALLED_MARKER}" ]; then
    echo "FAILED: CuPy wheel-install fixture did not run!" >&2
    exit 1
fi
if [ -e "${CLEANUP_CALLED_MARKER}" ]; then
    echo "FAILED: failed CuPy checkout was deleted before diagnosis!" >&2
    exit 1
fi

echo "PASSED CuPy wheel failure-status tests!"
