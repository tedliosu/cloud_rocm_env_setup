#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly TEST_BIN_DIR
TEST_ENV_DIR="${TEST_TMP_DIR}/packaged_amd_rapids_pyenv"
readonly TEST_ENV_DIR
TEST_REQUIREMENTS="${TEST_TMP_DIR}/requirements.txt"
readonly TEST_REQUIREMENTS
PROJECT_REQUIREMENTS="$(realpath \
    "${SCRIPT_DIR}/../etc/packaged_rapids_requirements.txt")"
readonly PROJECT_REQUIREMENTS
TEST_CALL_LOG="${TEST_TMP_DIR}/calls.log"
readonly TEST_CALL_LOG

cleanup() {
    rm --recursive --force -- "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"
touch "${TEST_REQUIREMENTS}"
export TEST_CALL_LOG TEST_PYTHON_VERSION="3.12"

grep --fixed-strings --line-regexp --quiet -- \
    '--extra-index-url https://pypi.amd.com/rocm-7.2.0/simple/' \
    "${PROJECT_REQUIREMENTS}"
grep --fixed-strings --line-regexp --quiet \
    'amd-cupy==13.5.1' "${PROJECT_REQUIREMENTS}"
grep --fixed-strings --line-regexp --quiet \
    'amd-hipcim==25.10.0' "${PROJECT_REQUIREMENTS}"

# Preserve these expressions for the generated command doubles.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "%s\n" "${TEST_PYTHON_VERSION}"' \
    > "${TEST_BIN_DIR}/python3"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'mkdir --parents "${1}/bin"' \
    'printf "%s\n" "# Test activation fixture." > "${1}/bin/activate"' \
    'printf "virtualenv|%s\n" "${1}" >> "${TEST_CALL_LOG}"' \
    > "${TEST_BIN_DIR}/virtualenv"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'printf "pip" >> "${TEST_CALL_LOG}"' \
    'printf "|%s" "$@" >> "${TEST_CALL_LOG}"' \
    'printf "\n" >> "${TEST_CALL_LOG}"' \
    > "${TEST_BIN_DIR}/pip"
chmod +x "${TEST_BIN_DIR}/python3" "${TEST_BIN_DIR}/virtualenv" \
    "${TEST_BIN_DIR}/pip"
export PATH="${TEST_BIN_DIR}:${PATH}"

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

guarded_rm_rf() {
    [ "$#" -eq 1 ] && [ "$1" = "${TEST_ENV_DIR}" ] || return 1
    rm --recursive --force -- "$1"
}

install_amd_devcloud_packaged_rapids_environment \
    "${TEST_ENV_DIR}" "${TEST_REQUIREMENTS}" >/dev/null

grep --fixed-strings --line-regexp --quiet \
    "virtualenv|${TEST_ENV_DIR}" "${TEST_CALL_LOG}"
grep --fixed-strings --line-regexp --quiet \
    "pip|install|--requirement|${TEST_REQUIREMENTS}" "${TEST_CALL_LOG}"
if grep --fixed-strings --quiet -- '--no-deps' "${TEST_CALL_LOG}"; then
    echo "FAILED: packaged AMD RAPIDS setup bypassed wheel dependencies!" >&2
    exit 1
fi
if grep --fixed-strings --quiet -- '--extra-index-url' "${TEST_CALL_LOG}"; then
    echo "FAILED: setup duplicated package-index policy outside the manifest!" >&2
    exit 1
fi
grep --fixed-strings --line-regexp --quiet "pip|check" "${TEST_CALL_LOG}"

TEST_PYTHON_VERSION="3.11"
export TEST_PYTHON_VERSION
if install_amd_devcloud_packaged_rapids_environment \
    "${TEST_TMP_DIR}/wrong_python" "${TEST_REQUIREMENTS}" >/dev/null 2>&1; then
    echo "FAILED: packaged AMD RAPIDS setup accepted Python 3.11!" >&2
    exit 1
fi
[ ! -e "${TEST_TMP_DIR}/wrong_python" ]

echo "PASSED AMD DevCloud packaged RAPIDS setup tests!"
