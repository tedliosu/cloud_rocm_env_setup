#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
TEST_TMP_DIR="$(mktemp --directory)"
TEST_ROCM_ROOT="${TEST_TMP_DIR}/rocm-7.2.3"
TEST_ROCM_LINK="${TEST_TMP_DIR}/rocm"
TEST_REPORT="${TEST_TMP_DIR}/report"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

cd "${REPO_ROOT}/validate/bin"
source "../lib/vald_util_funcs.sh"

mkdir --parents "${TEST_ROCM_ROOT}/lib"
ln --symbolic "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}"

ROCM_HOME="/ambient/rocm"
LD_LIBRARY_PATH="/ambient/lib"
export ROCM_HOME LD_LIBRARY_PATH
canonicalize_rocm_root "${TEST_ROCM_LINK}" > "${TEST_REPORT}"
[ "$(<"${TEST_REPORT}")" = "${TEST_ROCM_ROOT}" ]
[ "${ROCM_HOME}" = "/ambient/rocm" ]
[ "${LD_LIBRARY_PATH}" = "/ambient/lib" ]

if canonicalize_rocm_root >/dev/null 2>&1 ||
    canonicalize_rocm_root one two >/dev/null 2>&1; then
    echo "FAILED: ROCm root canonicalization accepted invalid arguments!" >&2
    exit 1
fi

for _invalid_result in "" "relative/rocm" $'/first/root\n/second/root' \
    "${TEST_TMP_DIR}/missing"; do
    if canonicalize_rocm_root \
        "${_invalid_result}" >/dev/null 2>&1; then
        echo "FAILED: ROCm root canonicalization accepted '${_invalid_result}'!" >&2
        exit 1
    fi
done

mkdir "${TEST_TMP_DIR}/rocm-without-lib"
if canonicalize_rocm_root \
    "${TEST_TMP_DIR}/rocm-without-lib" >/dev/null 2>&1; then
    echo "FAILED: ROCm root canonicalization accepted a root without lib!" >&2
    exit 1
fi

[ "$(select_cupy_rocm_home "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}")" = \
    "${TEST_ROCM_LINK}" ]
mkdir --parents "${TEST_TMP_DIR}/other-rocm/lib"
if select_cupy_rocm_home "${TEST_ROCM_ROOT}" \
    "${TEST_TMP_DIR}/other-rocm" >/dev/null 2>&1; then
    echo "FAILED: CuPy ROCM_HOME accepted a different selected stack!" >&2
    exit 1
fi

echo "PASSED ROCm validation-environment tests!"
