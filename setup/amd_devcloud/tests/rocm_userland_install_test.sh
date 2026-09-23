#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly TEST_BIN_DIR
INSTALL_CALLS="${TEST_TMP_DIR}/install-calls"
readonly INSTALL_CALLS

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--set-home" ]' \
    '[ "$2" = "env" ]' \
    '[ "$3" = "DEBIAN_FRONTEND=noninteractive" ]' \
    '[ "$4" = "NEEDRESTART_MODE=a" ]' \
    '[ "$5" = "apt-get" ]' \
    '[ "$6" = "install" ]' \
    '[ "$7" = "--assume-yes" ]' \
    '[ "$8" = "${TEST_ROCM_PACKAGE}=${TEST_ROCM_VERSION}" ]' \
    '[ "$#" -eq 8 ]' \
    'printf "%s\n" "$*" >> "${TEST_INSTALL_CALLS}"' \
    'exit "${TEST_INSTALL_STATUS}"' \
    > "${TEST_BIN_DIR}/sudo"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--show" ]' \
    '[ "$2" = "${TEST_DPKG_QUERY_FORMAT}" ]' \
    '[ "$3" = "${TEST_ROCM_PACKAGE}" ]' \
    '[ "$#" -eq 3 ]' \
    '[ "${TEST_DPKG_QUERY_STATUS}" -eq 0 ] || exit "${TEST_DPKG_QUERY_STATUS}"' \
    'printf "%s\t%s\n" "${TEST_PACKAGE_STATUS}" "${TEST_INSTALLED_VERSION}"' \
    > "${TEST_BIN_DIR}/dpkg-query"

printf '%s\n' '#!/bin/bash' 'exit 64' > "${TEST_BIN_DIR}/apt-get"
chmod +x "${TEST_BIN_DIR}"/*
export PATH="${TEST_BIN_DIR}:/usr/bin:/bin"

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

export TEST_ROCM_PACKAGE="${AMD_DEVCLOUD_ROCM_METAPACKAGE}"
export TEST_ROCM_VERSION="${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}"
export TEST_INSTALL_CALLS="${INSTALL_CALLS}"
# shellcheck disable=SC2016 # Match dpkg-query's literal format expression.
export TEST_DPKG_QUERY_FORMAT='--showformat=${db:Status-Status}\t${Version}\n'

_amd_devcloud_rocm_alternative_matches_versioned_root() {
    [ "${TEST_ROCM_ALTERNATIVE_MATCHES}" -eq 1 ]
}

reset_observations() {
    : > "${INSTALL_CALLS}"
    TEST_INSTALL_STATUS=0
    TEST_DPKG_QUERY_STATUS=0
    TEST_PACKAGE_STATUS="installed"
    TEST_INSTALLED_VERSION="${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}"
    TEST_ROCM_ALTERNATIVE_MATCHES=1
    export TEST_INSTALL_STATUS TEST_DPKG_QUERY_STATUS TEST_PACKAGE_STATUS
    export TEST_INSTALLED_VERSION TEST_ROCM_ALTERNATIVE_MATCHES
}

expect_rejection() {
    local _description="$1"
    local _expected_install_calls="$2"

    if install_amd_devcloud_rocm_userland >/dev/null 2>&1; then
        echo "FAILED: ${_description} was accepted!" >&2
        exit 1
    fi
    if [ "$(wc --lines < "${INSTALL_CALLS}")" -ne \
        "${_expected_install_calls}" ]; then
        echo "FAILED: ${_description} did not reach the expected install step!" >&2
        exit 1
    fi
}

reset_observations
# shellcheck disable=SC2119 # Exercise the documented zero-argument interface.
install_amd_devcloud_rocm_userland >/dev/null
if [ "$(wc --lines < "${INSTALL_CALLS}")" -ne 1 ]; then
    echo "FAILED: successful ROCm userland setup did not run one install!" >&2
    exit 1
fi

reset_observations
# shellcheck disable=SC2119 # Exercise rejection of an unexpected argument.
if install_amd_devcloud_rocm_userland unexpected >/dev/null 2>&1; then
    echo "FAILED: ROCm userland installation accepted an argument!" >&2
    exit 1
fi
if [ -s "${INSTALL_CALLS}" ]; then
    echo "FAILED: argument rejection reached ROCm package installation!" >&2
    exit 1
fi

reset_observations
TEST_INSTALL_STATUS=21
export TEST_INSTALL_STATUS
expect_rejection "failed ROCm userland installation" 1

reset_observations
TEST_DPKG_QUERY_STATUS=22
export TEST_DPKG_QUERY_STATUS
expect_rejection "failed ROCm package-state query" 1

reset_observations
TEST_PACKAGE_STATUS="config-files"
export TEST_PACKAGE_STATUS
expect_rejection "incomplete ROCm package state" 1

reset_observations
TEST_INSTALLED_VERSION="unexpected"
export TEST_INSTALLED_VERSION
expect_rejection "unexpected ROCm package version" 1

reset_observations
TEST_ROCM_ALTERNATIVE_MATCHES=0
export TEST_ROCM_ALTERNATIVE_MATCHES
expect_rejection "wrong ROCm alternative target" 1

echo "PASSED AMD DevCloud ROCm userland-install tests!"
