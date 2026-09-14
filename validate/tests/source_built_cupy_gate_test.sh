#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
TEST_TMP_DIR="$(mktemp --directory)"
TEST_ENV_DIR="${TEST_TMP_DIR}/source_built_cupy_env"
TEST_LIB_DIR="${TEST_TMP_DIR}/validation_lib"
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
TEST_CALL_LOG="${TEST_TMP_DIR}/python_calls.log"
STRICT_FLAG="--fail-on-no-source-built-cupy-env"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

cd "${REPO_ROOT}/validate/bin"
source "../lib/vald_util_funcs.sh"

mkdir --parents "${TEST_ENV_DIR}/bin" "${TEST_LIB_DIR}" "${TEST_BIN_DIR}"
printf '%s\n' '# Test activation fixture intentionally has no side effects.' \
    > "${TEST_ENV_DIR}/bin/activate"
touch "${TEST_LIB_DIR}/cupy_numpy_smoke.py" "${TEST_LIB_DIR}/numba_smoke.py"

# The single quotes intentionally preserve these expressions for the generated
#     Python-command test double rather than expanding them in this test runner.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '_script_basename="$(basename "${1}")"' \
    'printf "%s|%s\n" "${_script_basename}" "${LD_LIBRARY_PATH:-}" >> "${TEST_CALL_LOG}"' \
    '[ "${FAIL_SCRIPT_BASENAME:-}" != "${_script_basename}" ]' \
    > "${TEST_BIN_DIR}/python3"
chmod +x "${TEST_BIN_DIR}/python3"
export PATH="${TEST_BIN_DIR}:${PATH}"
export TEST_CALL_LOG
export LD_LIBRARY_PATH="/test/rocm/lib"

validate_source_built_cupy_env "${TEST_TMP_DIR}/absent" "bin/activate" \
    "${TEST_LIB_DIR}" "/test/tbb/lib:/test/rocm/lib" 0 "${STRICT_FLAG}" >/dev/null
[ ! -e "${TEST_CALL_LOG}" ]

if validate_source_built_cupy_env "${TEST_TMP_DIR}/absent" "bin/activate" \
    "${TEST_LIB_DIR}" "/test/tbb/lib:/test/rocm/lib" 1 "${STRICT_FLAG}" >/dev/null 2>&1; then
    echo "FAILED: strict presence accepted an absent environment!" >&2
    exit 1
fi

: > "${TEST_CALL_LOG}"
validate_source_built_cupy_env "${TEST_ENV_DIR}" "bin/activate" \
    "${TEST_LIB_DIR}" "/test/tbb/lib:/test/rocm/lib" 0 "${STRICT_FLAG}" >/dev/null
[ "$(cat "${TEST_CALL_LOG}")" = "$(printf '%s\n%s' \
    'cupy_numpy_smoke.py|/test/rocm/lib' \
    'numba_smoke.py|/test/tbb/lib:/test/rocm/lib')" ]

: > "${TEST_CALL_LOG}"
if FAIL_SCRIPT_BASENAME="cupy_numpy_smoke.py" \
    validate_source_built_cupy_env "${TEST_ENV_DIR}" "bin/activate" \
        "${TEST_LIB_DIR}" "/test/tbb/lib:/test/rocm/lib" 0 "${STRICT_FLAG}" >/dev/null 2>&1; then
    echo "FAILED: the environment check reported success after CuPy validation failed!" >&2
    exit 1
fi
[ "$(cat "${TEST_CALL_LOG}")" = "cupy_numpy_smoke.py|/test/rocm/lib" ]

: > "${TEST_CALL_LOG}"
if FAIL_SCRIPT_BASENAME="numba_smoke.py" \
    validate_source_built_cupy_env "${TEST_ENV_DIR}" "bin/activate" \
        "${TEST_LIB_DIR}" "/test/tbb/lib:/test/rocm/lib" 0 "${STRICT_FLAG}" >/dev/null 2>&1; then
    echo "FAILED: the environment check reported success after Numba/TBB validation failed!" >&2
    exit 1
fi
[ "$(cat "${TEST_CALL_LOG}")" = "$(printf '%s\n%s' \
    'cupy_numpy_smoke.py|/test/rocm/lib' \
    'numba_smoke.py|/test/tbb/lib:/test/rocm/lib')" ]

echo "PASSED source-built CuPy environment gate tests!"
