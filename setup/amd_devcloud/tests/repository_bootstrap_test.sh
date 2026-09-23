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
UPDATE_CALLS="${TEST_TMP_DIR}/update-calls"
readonly UPDATE_CALLS

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--tries=3" ]' \
    '[ "$2" = "--timeout=30" ]' \
    'case "$3" in --output-document=*) ;; *) exit 64 ;; esac' \
    '[ "$4" = "${TEST_BOOTSTRAP_URL}" ]' \
    '[ "${TEST_WGET_STATUS}" -eq 0 ] || exit "${TEST_WGET_STATUS}"' \
    'printf "mock AMD package\n" > "${3#--output-document=}"' \
    > "${TEST_BIN_DIR}/wget"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$*" = "--check --status" ]' \
    'IFS= read -r checksum_line' \
    'case "${checksum_line}" in "${TEST_BOOTSTRAP_SHA256}  "*) ;; *) exit 64 ;; esac' \
    'exit "${TEST_SHA256_STATUS}"' \
    > "${TEST_BIN_DIR}/sha256sum"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--field" ]' \
    '[ "$3" = "Version" ]' \
    '[ "${TEST_DPKG_DEB_STATUS}" -eq 0 ] || exit "${TEST_DPKG_DEB_STATUS}"' \
    'printf "%s\n" "${TEST_PACKAGE_METADATA_VERSION}"' \
    > "${TEST_BIN_DIR}/dpkg-deb"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--set-home" ]' \
    'case "${2:-} ${3:-}" in' \
    '    "apt-get install")' \
    '        [ "$4" = "--assume-yes" ]' \
    '        [ -f "$5" ]' \
    '        printf "%s\n" "$*" >> "${TEST_INSTALL_CALLS}"' \
    '        exit "${TEST_INSTALL_STATUS}"' \
    '        ;;' \
    '    "apt-get update")' \
    '        [ "$#" -eq 4 ]' \
    '        [ "$4" = "--option=APT::Update::Error-Mode=any" ]' \
    '        printf "%s\n" "$*" >> "${TEST_UPDATE_CALLS}"' \
    '        exit "${TEST_UPDATE_STATUS}"' \
    '        ;;' \
    '    *) exit 64 ;;' \
    'esac' \
    > "${TEST_BIN_DIR}/sudo"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--show" ]' \
    '[ "$2" = "${TEST_DPKG_QUERY_FORMAT}" ]' \
    '[ "$3" = "amdgpu-install" ]' \
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

export TEST_BOOTSTRAP_URL="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}"
export TEST_BOOTSTRAP_SHA256="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_SHA256}"
export TEST_INSTALL_CALLS="${INSTALL_CALLS}"
export TEST_UPDATE_CALLS="${UPDATE_CALLS}"
# shellcheck disable=SC2016 # Match dpkg-query's literal format expression.
export TEST_DPKG_QUERY_FORMAT='--showformat=${db:Status-Status}\t${Version}\n'

TEST_COMMAND_ARTIFACTS=""
TEST_PATH_ARTIFACTS=""

_amd_devcloud_collect_command_artifacts() {
    [ -z "${TEST_COMMAND_ARTIFACTS}" ] ||
        printf '%s\n' "${TEST_COMMAND_ARTIFACTS}"
}

_amd_devcloud_collect_path_artifacts() {
    [ -z "${TEST_PATH_ARTIFACTS}" ] || printf '%s\n' "${TEST_PATH_ARTIFACTS}"
}

reset_observations() {
    : > "${INSTALL_CALLS}"
    : > "${UPDATE_CALLS}"
    TEST_WGET_STATUS=0
    TEST_SHA256_STATUS=0
    TEST_DPKG_DEB_STATUS=0
    TEST_PACKAGE_METADATA_VERSION="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}"
    TEST_INSTALL_STATUS=0
    TEST_UPDATE_STATUS=0
    TEST_DPKG_QUERY_STATUS=0
    TEST_PACKAGE_STATUS="installed"
    TEST_INSTALLED_VERSION="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}"
    TEST_COMMAND_ARTIFACTS="$(_amd_devcloud_expected_repository_bootstrap_command_artifacts)"
    TEST_PATH_ARTIFACTS="$(_amd_devcloud_expected_repository_bootstrap_path_artifacts)"
    export TEST_WGET_STATUS TEST_SHA256_STATUS TEST_DPKG_DEB_STATUS
    export TEST_PACKAGE_METADATA_VERSION TEST_INSTALL_STATUS TEST_UPDATE_STATUS
    export TEST_DPKG_QUERY_STATUS TEST_PACKAGE_STATUS TEST_INSTALLED_VERSION
}

expect_rejection() {
    local _description="$1"
    local _expected_install_calls="$2"
    local _expected_update_calls="$3"

    # shellcheck disable=SC2119 # The production function deliberately rejects arguments.
    if install_amd_devcloud_repository_bootstrap >/dev/null 2>&1; then
        echo "FAILED: ${_description} was accepted!" >&2
        exit 1
    fi
    if [ "$(wc --lines < "${INSTALL_CALLS}")" -ne \
        "${_expected_install_calls}" ] ||
        [ "$(wc --lines < "${UPDATE_CALLS}")" -ne \
            "${_expected_update_calls}" ]; then
        echo "FAILED: ${_description} did not reach the expected mutation step!" >&2
        exit 1
    fi
}

reset_observations
# shellcheck disable=SC2119 # Exercise the documented zero-argument interface.
install_amd_devcloud_repository_bootstrap >/dev/null
if [ "$(wc --lines < "${INSTALL_CALLS}")" -ne 1 ] ||
    [ "$(wc --lines < "${UPDATE_CALLS}")" -ne 1 ]; then
    echo "FAILED: successful repository bootstrap did not install and update!" >&2
    exit 1
fi

reset_observations
TEST_WGET_STATUS=21
export TEST_WGET_STATUS
expect_rejection "failed repository-bootstrap download" 0 0

reset_observations
TEST_SHA256_STATUS=22
export TEST_SHA256_STATUS
expect_rejection "failed repository-bootstrap checksum" 0 0

reset_observations
TEST_PACKAGE_METADATA_VERSION="unexpected"
export TEST_PACKAGE_METADATA_VERSION
expect_rejection "unexpected downloaded package version" 0 0

reset_observations
TEST_INSTALL_STATUS=23
export TEST_INSTALL_STATUS
expect_rejection "failed repository-bootstrap installation" 1 0

reset_observations
TEST_UPDATE_STATUS=24
export TEST_UPDATE_STATUS
expect_rejection "failed repository metadata refresh" 1 1

reset_observations
TEST_INSTALLED_VERSION="unexpected"
export TEST_INSTALLED_VERSION
expect_rejection "unexpected installed bootstrap version" 1 1

reset_observations
TEST_COMMAND_ARTIFACTS="amdgpu-install"
expect_rejection "incomplete repository command artifacts" 1 1

reset_observations
TEST_PATH_ARTIFACTS+=$'\n/opt/rocm'
expect_rejection "unexpected repository path artifact" 1 1

echo "PASSED AMD DevCloud repository-bootstrap tests!"
