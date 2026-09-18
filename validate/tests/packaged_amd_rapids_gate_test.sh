#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
VALIDATE_MAIN="${REPO_ROOT}/validate/bin/validate_main.sh"
TEST_TMP_DIR="$(mktemp --directory)"
TEST_ENV_DIR="${TEST_TMP_DIR}/packaged_amd_rapids_env"
TEST_LIB_DIR="${TEST_TMP_DIR}/validation_lib"
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
TEST_CALL_LOG="${TEST_TMP_DIR}/python_calls.log"
STRICT_FLAG="--fail-on-no-packaged-amd-rapids-env"
TEST_ROCM_ROOT="${TEST_TMP_DIR}/rocm-7.2.3"
TEST_ROCM_LINK="${TEST_TMP_DIR}/rocm"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

cd "${REPO_ROOT}/validate/bin"
source "../lib/vald_util_funcs.sh"
source "../lib/vald_shared_vars.sh"

"${VALIDATE_MAIN}" --help | grep --fixed-strings --quiet -- "${STRICT_FLAG}"

mkdir --parents "${TEST_ENV_DIR}/bin" "${TEST_LIB_DIR}" "${TEST_BIN_DIR}" \
    "${TEST_ROCM_ROOT}/lib"
ln --symbolic "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}"
printf '%s\n' '# Test activation fixture intentionally has no side effects.' \
    > "${TEST_ENV_DIR}/bin/activate"
touch "${TEST_LIB_DIR}/cupy_numpy_smoke.py" \
    "${TEST_LIB_DIR}/numba_smoke.py" \
    "${TEST_LIB_DIR}/hipcim_canny_smoke.py"

# Preserve these expressions for the generated Python-command test double.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '_script_basename="$(basename "${1}")"' \
    'shift' \
    'printf "%s|%s|%s|%s|%s\n" "${_script_basename}" "${LD_LIBRARY_PATH:-}" "${ROCM_HOME:-}" "${CUPY_ACCELERATORS:-}" "$*" >> "${TEST_CALL_LOG}"' \
    '[ "${FAIL_SCRIPT_BASENAME:-}" != "${_script_basename}" ]' \
    > "${TEST_BIN_DIR}/python3"
chmod +x "${TEST_BIN_DIR}/python3"
export PATH="${TEST_BIN_DIR}:${PATH}"
export TEST_CALL_LOG
export LD_LIBRARY_PATH="/test/rocm/lib"

validate_packaged_amd_rapids_env "${TEST_TMP_DIR}/absent" "bin/activate" \
    "${TEST_LIB_DIR}" "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}" \
    "/test/tbb/lib:/test/rocm/lib" 0 \
    "${STRICT_FLAG}" "${HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT}" >/dev/null
[ ! -e "${TEST_CALL_LOG}" ]

if validate_packaged_amd_rapids_env "${TEST_TMP_DIR}/absent" "bin/activate" \
    "${TEST_LIB_DIR}" "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}" \
    "/test/tbb/lib:/test/rocm/lib" 1 \
    "${STRICT_FLAG}" "${HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT}" \
    >/dev/null 2>&1; then
    echo "FAILED: strict presence accepted an absent packaged environment!" >&2
    exit 1
fi

: > "${TEST_CALL_LOG}"
validate_packaged_amd_rapids_env "${TEST_ENV_DIR}" "bin/activate" \
    "${TEST_LIB_DIR}" "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}" \
    "/test/tbb/lib:/test/rocm/lib" 0 \
    "${STRICT_FLAG}" "${HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT}" >/dev/null
[ "$(cat "${TEST_CALL_LOG}")" = "$(printf '%s\n%s\n%s' \
    "cupy_numpy_smoke.py|/test/rocm/lib|${TEST_ROCM_LINK}|cub|" \
    'numba_smoke.py|/test/tbb/lib:/test/rocm/lib|||' \
    "hipcim_canny_smoke.py|/test/rocm/lib|${TEST_ROCM_LINK}|cub|--max-disagreement-percent 0.0")" ]

for _failed_script in cupy_numpy_smoke.py numba_smoke.py hipcim_canny_smoke.py; do
    : > "${TEST_CALL_LOG}"
    if FAIL_SCRIPT_BASENAME="${_failed_script}" \
        validate_packaged_amd_rapids_env "${TEST_ENV_DIR}" "bin/activate" \
            "${TEST_LIB_DIR}" "${TEST_ROCM_ROOT}" "${TEST_ROCM_LINK}" \
            "/test/tbb/lib:/test/rocm/lib" \
            0 "${STRICT_FLAG}" "${HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT}" \
            >/dev/null 2>&1; then
        echo "FAILED: packaged gate accepted '${_failed_script}' failure!" >&2
        exit 1
    fi
done

echo "PASSED packaged AMD RAPIDS environment gate tests!"
