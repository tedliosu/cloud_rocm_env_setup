#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly TEST_BIN_DIR

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"

# Single quotes preserve these expressions for the generated command doubles.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "${TEST_LSPCI_STATUS:-0}" -eq 0 ] || exit "${TEST_LSPCI_STATUS}"' \
    '[ "$*" = "-Dn -d 1002:74b5" ]' \
    'printf "%s" "${TEST_PCI_OUTPUT:-}"' \
    > "${TEST_BIN_DIR}/lspci"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "${TEST_DPKG_STATUS:-0}" -eq 0 ] || exit "${TEST_DPKG_STATUS}"' \
    '[ "${1:-}" = "--show" ]' \
    'printf "%s" "${TEST_PACKAGE_OUTPUT:-}"' \
    > "${TEST_BIN_DIR}/dpkg-query"
chmod +x "${TEST_BIN_DIR}/lspci" "${TEST_BIN_DIR}/dpkg-query"
export PATH="${TEST_BIN_DIR}:/usr/bin:/bin"

TEST_PCI_OUTPUT=$'0000:83:00.0 1200: 1002:74b5\n'
TEST_PACKAGE_OUTPUT=$'bash\tinstalled\n'
TEST_LSPCI_STATUS=0
TEST_DPKG_STATUS=0
TEST_AMDGPU_LOADED=0
TEST_KFD_PRESENT=0
TEST_COMMAND_ARTIFACTS=""
TEST_PATH_ARTIFACTS=""
export TEST_PCI_OUTPUT TEST_PACKAGE_OUTPUT TEST_LSPCI_STATUS TEST_DPKG_STATUS

_amd_devcloud_amdgpu_module_is_loaded() {
    [ "${TEST_AMDGPU_LOADED}" -eq 1 ]
}

_amd_devcloud_kfd_is_present() {
    [ "${TEST_KFD_PRESENT}" -eq 1 ]
}

_amd_devcloud_collect_command_artifacts() {
    [ -z "${TEST_COMMAND_ARTIFACTS}" ] ||
        printf '%s\n' "${TEST_COMMAND_ARTIFACTS}"
}

_amd_devcloud_collect_path_artifacts() {
    [ -z "${TEST_PATH_ARTIFACTS}" ] || printf '%s\n' "${TEST_PATH_ARTIFACTS}"
}

reset_observations() {
    TEST_PCI_OUTPUT=$'0000:83:00.0 1200: 1002:74b5\n'
    TEST_PACKAGE_OUTPUT=$'bash\tinstalled\n'
    TEST_LSPCI_STATUS=0
    TEST_DPKG_STATUS=0
    TEST_AMDGPU_LOADED=0
    TEST_KFD_PRESENT=0
    TEST_COMMAND_ARTIFACTS=""
    TEST_PATH_ARTIFACTS=""
    unset SHOW_PLAN_ONLY
}

expect_acceptance() {
    local _milestones_dir="$1"

    if ! check_amd_devcloud_system_upgrade_admission_dont_wrap \
        "${_milestones_dir}" >/dev/null 2>&1; then
        echo "FAILED: expected DevCloud system-upgrade admission acceptance!" >&2
        exit 1
    fi
}

expect_rejection() {
    local _milestones_dir="$1"

    if check_amd_devcloud_system_upgrade_admission_dont_wrap \
        "${_milestones_dir}" >/dev/null 2>&1; then
        echo "FAILED: expected DevCloud system-upgrade admission rejection!" >&2
        exit 1
    fi
}

BARE_DIR="${TEST_TMP_DIR}/bare"
UPGRADED_DIR="${TEST_TMP_DIR}/upgraded"
TMUX_ONLY_DIR="${TEST_TMP_DIR}/tmux-only"
PENDING_DIR="${TEST_TMP_DIR}/pending"
COMPLETED_DIR="${TEST_TMP_DIR}/completed"
CONTRADICTORY_DIR="${TEST_TMP_DIR}/contradictory"
BAD_MARKER_DIR="${TEST_TMP_DIR}/bad-marker"
BAD_MILESTONES_PATH="${TEST_TMP_DIR}/not-a-directory"
mkdir "${BARE_DIR}" "${UPGRADED_DIR}" "${TMUX_ONLY_DIR}" "${PENDING_DIR}" \
    "${COMPLETED_DIR}" "${CONTRADICTORY_DIR}" "${BAD_MARKER_DIR}"
touch "${BAD_MILESTONES_PATH}"

reset_observations
expect_acceptance "${BARE_DIR}"

reset_observations
expect_acceptance "${TEST_TMP_DIR}/not-created-yet"

reset_observations
expect_rejection "${BAD_MILESTONES_PATH}"

reset_observations
expect_rejection "${TEST_TMP_DIR}/missing-parent/milestones"

touch "${UPGRADED_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done"
expect_acceptance "${UPGRADED_DIR}"

touch "${TMUX_ONLY_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done"
expect_rejection "${TMUX_ONLY_DIR}"

touch "${PENDING_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
    "${PENDING_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
    "${PENDING_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.pending"
expect_acceptance "${PENDING_DIR}"

touch "${COMPLETED_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
    "${COMPLETED_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
    "${COMPLETED_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done"
expect_acceptance "${COMPLETED_DIR}"

reset_observations
TEST_PCI_OUTPUT=""
expect_rejection "${BARE_DIR}"

reset_observations
TEST_PCI_OUTPUT=$'0000:83:00.0 1200: 1002:74b5\n0000:84:00.0 1200: 1002:74b5\n'
expect_rejection "${BARE_DIR}"

reset_observations
TEST_AMDGPU_LOADED=1
expect_rejection "${BARE_DIR}"

reset_observations
TEST_KFD_PRESENT=1
expect_rejection "${BARE_DIR}"

reset_observations
TEST_PACKAGE_OUTPUT=$'amdgpu-install\tinstalled\n'
expect_rejection "${BARE_DIR}"

reset_observations
TEST_PACKAGE_OUTPUT=$'rocm7.2.3\tconfig-files\n'
expect_rejection "${BARE_DIR}"

reset_observations
TEST_COMMAND_ARTIFACTS="rocminfo"
expect_rejection "${BARE_DIR}"

reset_observations
TEST_PATH_ARTIFACTS="/opt/rocm"
expect_rejection "${BARE_DIR}"

reset_observations
TEST_LSPCI_STATUS=23
expect_rejection "${BARE_DIR}"

reset_observations
TEST_DPKG_STATUS=24
expect_rejection "${BARE_DIR}"

touch "${CONTRADICTORY_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.pending"
reset_observations
expect_rejection "${CONTRADICTORY_DIR}"
touch "${CONTRADICTORY_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
    "${CONTRADICTORY_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
    "${CONTRADICTORY_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done"
expect_rejection "${CONTRADICTORY_DIR}"

mkdir "${BAD_MARKER_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done"
reset_observations
expect_rejection "${BAD_MARKER_DIR}"

reset_observations
SHOW_PLAN_ONLY=1
TEST_LSPCI_STATUS=25
TEST_DPKG_STATUS=26
expect_acceptance "${TEST_TMP_DIR}/missing-plan-directory"

echo "PASSED AMD DevCloud system-upgrade admission tests!"
