#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly TEST_BIN_DIR
KERNEL_INSTALL_CALLS="${TEST_TMP_DIR}/kernel-install-calls"
readonly KERNEL_INSTALL_CALLS
DRIVER_INSTALL_CALLS="${TEST_TMP_DIR}/driver-install-calls"
readonly DRIVER_INSTALL_CALLS

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$*" = "--kernel-release" ]' \
    '[ "${TEST_UNAME_STATUS}" -eq 0 ] || exit "${TEST_UNAME_STATUS}"' \
    'printf "%s\n" "${TEST_KERNEL_RELEASE}"' \
    > "${TEST_BIN_DIR}/uname"

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
    'case "${8:-}" in' \
    '    "linux-headers-${TEST_KERNEL_RELEASE}")' \
    '        [ "$#" -eq 9 ]' \
    '        [ "$9" = "linux-modules-extra-${TEST_KERNEL_RELEASE}" ]' \
    '        printf "%s\n" "$*" >> "${TEST_KERNEL_INSTALL_CALLS}"' \
    '        exit "${TEST_KERNEL_INSTALL_STATUS}"' \
    '        ;;' \
    '    "${TEST_AMDGPU_PACKAGE}=${TEST_AMDGPU_VERSION}")' \
    '        [ "$#" -eq 9 ]' \
    '        [ "$9" = "${TEST_AMD_SMI_PACKAGE}=${TEST_AMD_SMI_VERSION}" ]' \
    '        printf "%s\n" "$*" >> "${TEST_DRIVER_INSTALL_CALLS}"' \
    '        exit "${TEST_DRIVER_INSTALL_STATUS}"' \
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
    'case "$3" in' \
    '    "linux-headers-${TEST_KERNEL_RELEASE}")' \
    '        printf "%s\t%s\n" "${TEST_HEADERS_STATUS}" "${TEST_HEADERS_VERSION}"' \
    '        ;;' \
    '    "linux-modules-extra-${TEST_KERNEL_RELEASE}")' \
    '        printf "%s\t%s\n" "${TEST_MODULES_STATUS}" "${TEST_MODULES_VERSION}"' \
    '        ;;' \
    '    "${TEST_AMDGPU_PACKAGE}")' \
    '        printf "%s\t%s\n" "${TEST_AMDGPU_STATUS}" "${TEST_INSTALLED_AMDGPU_VERSION}"' \
    '        ;;' \
    '    "${TEST_AMD_SMI_PACKAGE}")' \
    '        printf "%s\t%s\n" "${TEST_AMD_SMI_STATUS}" "${TEST_INSTALLED_AMD_SMI_VERSION}"' \
    '        ;;' \
    '    *) exit 64 ;;' \
    'esac' \
    > "${TEST_BIN_DIR}/dpkg-query"

printf '%s\n' '#!/bin/bash' 'exit 64' > "${TEST_BIN_DIR}/apt-get"
chmod +x "${TEST_BIN_DIR}"/*
export PATH="${TEST_BIN_DIR}:/usr/bin:/bin"

test_rocm_alternative_resolution() (
    AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH="${TEST_TMP_DIR}/rocm"
    AMD_DEVCLOUD_ROCM_VERSIONED_ROOT="${TEST_TMP_DIR}/rocm-7.2.3"
    local _wrong_root="${TEST_TMP_DIR}/rocm-wrong"

    mkdir "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}" "${_wrong_root}"
    ln --symbolic "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}" \
        "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}"
    # shellcheck source=../lib/amd_devcloud_funcs.sh
    . "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

    if ! _amd_devcloud_rocm_alternative_matches_versioned_root; then
        echo "FAILED: expected the exact ROCm alternative target to pass!" >&2
        exit 1
    fi
    unlink "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}"
    ln --symbolic "${_wrong_root}" "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}"
    if _amd_devcloud_rocm_alternative_matches_versioned_root; then
        echo "FAILED: unexpected ROCm alternative target was accepted!" >&2
        exit 1
    fi
)

test_rocm_alternative_resolution

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

export TEST_AMDGPU_PACKAGE="${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}"
export TEST_AMDGPU_VERSION="${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}"
export TEST_AMD_SMI_PACKAGE="${AMD_DEVCLOUD_AMD_SMI_PACKAGE}"
export TEST_AMD_SMI_VERSION="${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}"
export TEST_KERNEL_INSTALL_CALLS="${KERNEL_INSTALL_CALLS}"
export TEST_DRIVER_INSTALL_CALLS="${DRIVER_INSTALL_CALLS}"
# shellcheck disable=SC2016 # Match dpkg-query's literal format expression.
export TEST_DPKG_QUERY_FORMAT='--showformat=${db:Status-Status}\t${Version}\n'

_amd_devcloud_rocm_alternative_matches_versioned_root() {
    [ "${TEST_ROCM_ALTERNATIVE_MATCHES}" -eq 1 ]
}

_amd_devcloud_amd_smi_is_executable() {
    [ "${TEST_AMD_SMI_EXECUTABLE}" -eq 1 ]
}

reset_observations() {
    : > "${KERNEL_INSTALL_CALLS}"
    : > "${DRIVER_INSTALL_CALLS}"
    TEST_KERNEL_RELEASE="6.8.0-test"
    TEST_UNAME_STATUS=0
    TEST_KERNEL_INSTALL_STATUS=0
    TEST_DRIVER_INSTALL_STATUS=0
    TEST_HEADERS_STATUS="installed"
    TEST_HEADERS_VERSION="6.8.0"
    TEST_MODULES_STATUS="installed"
    TEST_MODULES_VERSION="6.8.0"
    TEST_AMDGPU_STATUS="installed"
    TEST_INSTALLED_AMDGPU_VERSION="${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}"
    TEST_AMD_SMI_STATUS="installed"
    TEST_INSTALLED_AMD_SMI_VERSION="${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}"
    TEST_ROCM_ALTERNATIVE_MATCHES=1
    TEST_AMD_SMI_EXECUTABLE=1
    export TEST_KERNEL_RELEASE TEST_UNAME_STATUS TEST_KERNEL_INSTALL_STATUS
    export TEST_DRIVER_INSTALL_STATUS
    export TEST_HEADERS_STATUS TEST_HEADERS_VERSION
    export TEST_MODULES_STATUS TEST_MODULES_VERSION
    export TEST_AMDGPU_STATUS TEST_INSTALLED_AMDGPU_VERSION
    export TEST_AMD_SMI_STATUS TEST_INSTALLED_AMD_SMI_VERSION
    export TEST_ROCM_ALTERNATIVE_MATCHES TEST_AMD_SMI_EXECUTABLE
}

expect_rejection() {
    local _description="$1"
    local _expected_kernel_calls="$2"
    local _expected_driver_calls="$3"

    # shellcheck disable=SC2119 # The production function deliberately rejects arguments.
    if install_amd_devcloud_driver >/dev/null 2>&1; then
        echo "FAILED: ${_description} was accepted!" >&2
        exit 1
    fi
    if [ "$(wc --lines < "${KERNEL_INSTALL_CALLS}")" -ne \
        "${_expected_kernel_calls}" ] ||
        [ "$(wc --lines < "${DRIVER_INSTALL_CALLS}")" -ne \
            "${_expected_driver_calls}" ]; then
        echo "FAILED: ${_description} did not reach the expected install step!" >&2
        exit 1
    fi
}

reset_observations
# shellcheck disable=SC2119 # Exercise the documented zero-argument interface.
install_amd_devcloud_driver >/dev/null
if [ "$(wc --lines < "${KERNEL_INSTALL_CALLS}")" -ne 1 ] ||
    [ "$(wc --lines < "${DRIVER_INSTALL_CALLS}")" -ne 1 ]; then
    echo "FAILED: successful driver setup did not run both install steps!" >&2
    exit 1
fi

reset_observations
TEST_UNAME_STATUS=21
export TEST_UNAME_STATUS
expect_rejection "failed running-kernel observation" 0 0

reset_observations
TEST_KERNEL_INSTALL_STATUS=22
export TEST_KERNEL_INSTALL_STATUS
expect_rejection "failed running-kernel package installation" 1 0

reset_observations
TEST_DRIVER_INSTALL_STATUS=23
export TEST_DRIVER_INSTALL_STATUS
expect_rejection "failed AMDGPU package installation" 1 1

reset_observations
TEST_HEADERS_STATUS="config-files"
export TEST_HEADERS_STATUS
expect_rejection "incomplete kernel-header package state" 1 1

reset_observations
TEST_MODULES_VERSION=""
export TEST_MODULES_VERSION
expect_rejection "missing kernel-modules package version" 1 1

reset_observations
TEST_INSTALLED_AMDGPU_VERSION="unexpected"
export TEST_INSTALLED_AMDGPU_VERSION
expect_rejection "unexpected AMDGPU package version" 1 1

reset_observations
TEST_INSTALLED_AMD_SMI_VERSION="unexpected"
export TEST_INSTALLED_AMD_SMI_VERSION
expect_rejection "unexpected AMD SMI package version" 1 1

reset_observations
TEST_ROCM_ALTERNATIVE_MATCHES=0
export TEST_ROCM_ALTERNATIVE_MATCHES
expect_rejection "wrong ROCm alternative target" 1 1

reset_observations
TEST_AMD_SMI_EXECUTABLE=0
export TEST_AMD_SMI_EXECUTABLE
expect_rejection "missing AMD SMI executable" 1 1

echo "PASSED AMD DevCloud driver-install tests!"
