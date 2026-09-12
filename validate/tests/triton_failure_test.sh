#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
readonly REPO_ROOT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TRITON_DIR="${TEST_TMP_DIR}/triton"
readonly TRITON_DIR
PYTHON_CALLED_MARKER="${TEST_TMP_DIR}/python-called"
readonly PYTHON_CALLED_MARKER
CLEANUP_CALLED_MARKER="${TEST_TMP_DIR}/cleanup-called"
readonly CLEANUP_CALLED_MARKER
LATER_STAGE_MARKER="${TEST_TMP_DIR}/later-stage"
readonly LATER_STAGE_MARKER
VALIDATION_OUTPUT="${TEST_TMP_DIR}/validation-output"
readonly VALIDATION_OUTPUT

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

cd "${REPO_ROOT}/validate/bin"
# shellcheck source=../lib/vald_util_funcs.sh
. "../lib/vald_util_funcs.sh"

set +e
(
    set -e
    git() {
        if [ "$#" -ge 3 ] && [ "$3" = "clone" ]; then
            mkdir --parents "${TRITON_DIR}"
        fi
        return 0
    }
    python3() {
        touch "${PYTHON_CALLED_MARKER}"
        return 23
    }
    guarded_rm_rf() {
        touch "${CLEANUP_CALLED_MARKER}"
    }

    validate_basic_triton "${TRITON_DIR}" v-test /test/tutorial.patch
    touch "${LATER_STAGE_MARKER}"
) >"${VALIDATION_OUTPUT}" 2>&1
validation_status="$?"
set -e

if [ "${validation_status}" -ne 1 ]; then
    echo "FAILED: Triton smoke failure did not reach its explicit status branch!" >&2
    exit 1
fi
if [ ! -f "${PYTHON_CALLED_MARKER}" ]; then
    echo "FAILED: Triton Python smoke fixture did not run!" >&2
    exit 1
fi
if ! grep --fixed-strings --quiet \
    "FAILED Triton fp16 matmul tutorial based smoke test!" \
    "${VALIDATION_OUTPUT}"; then
    echo "FAILED: Triton smoke failure diagnostic was not emitted!" >&2
    exit 1
fi
if [ -e "${CLEANUP_CALLED_MARKER}" ]; then
    echo "FAILED: failed Triton checkout was deleted before diagnosis!" >&2
    exit 1
fi
if [ -e "${LATER_STAGE_MARKER}" ]; then
    echo "FAILED: validation continued after the Triton smoke failed!" >&2
    exit 1
fi

echo "PASSED Triton validator failure-propagation test!"
