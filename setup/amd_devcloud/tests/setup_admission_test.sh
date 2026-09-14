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
TEST_PACKAGE_OUTPUT=$'bash\tinstalled\t5.2\n'
TEST_LSPCI_STATUS=0
TEST_DPKG_STATUS=0
TEST_AMDGPU_LOADED=0
TEST_KFD_PRESENT=0
TEST_ROCM_ALTERNATIVE_MATCHES=1
TEST_COMMAND_ARTIFACTS=""
TEST_PATH_ARTIFACTS=""
export TEST_PCI_OUTPUT TEST_PACKAGE_OUTPUT TEST_LSPCI_STATUS TEST_DPKG_STATUS

_amd_devcloud_amdgpu_module_is_loaded() {
    [ "${TEST_AMDGPU_LOADED}" -eq 1 ]
}

_amd_devcloud_kfd_is_present() {
    [ "${TEST_KFD_PRESENT}" -eq 1 ]
}

_amd_devcloud_rocm_alternative_matches_versioned_root() {
    [ "${TEST_ROCM_ALTERNATIVE_MATCHES}" -eq 1 ]
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
    TEST_PACKAGE_OUTPUT=$'bash\tinstalled\t5.2\n'
    TEST_LSPCI_STATUS=0
    TEST_DPKG_STATUS=0
    TEST_AMDGPU_LOADED=0
    TEST_KFD_PRESENT=0
    TEST_ROCM_ALTERNATIVE_MATCHES=1
    TEST_COMMAND_ARTIFACTS=""
    TEST_PATH_ARTIFACTS=""
    unset SHOW_PLAN_ONLY
}

set_repository_bootstrap_observations() {
    TEST_PACKAGE_OUTPUT=$'bash\tinstalled\t5.2\n'
    TEST_PACKAGE_OUTPUT+="amdgpu-install"$'\tinstalled\t'"${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}"$'\n'
    TEST_COMMAND_ARTIFACTS="$(printf '%s\n' \
        "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_COMMAND_ARTIFACTS[@]}")"
    TEST_PATH_ARTIFACTS="$(printf '%s\n' \
        "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PATH_ARTIFACTS[@]}")"
}

set_driver_observations() {
    set_repository_bootstrap_observations
    TEST_PACKAGE_OUTPUT+="${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}"$'\tinstalled\t'"${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}"$'\n'
    TEST_PACKAGE_OUTPUT+="${AMD_DEVCLOUD_AMD_SMI_PACKAGE}"$'\tinstalled\t'"${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}"$'\n'
    TEST_PACKAGE_OUTPUT+="${AMD_DEVCLOUD_ROCM_CORE_PACKAGE}"$'\tinstalled\t'"${AMD_DEVCLOUD_ROCM_CORE_PACKAGE_VERSION}"$'\n'
    TEST_PATH_ARTIFACTS="$(printf '%s\n' \
        "${AMD_DEVCLOUD_DRIVER_PATH_ARTIFACTS[@]}")"
}

set_rocm_userland_observations() {
    set_driver_observations
    TEST_PACKAGE_OUTPUT+="${AMD_DEVCLOUD_ROCM_METAPACKAGE}"$'\tinstalled\t'"${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}"$'\n'
}

expect_acceptance() {
    local _milestones_dir="$1"

    if ! check_amd_devcloud_setup_admission_dont_wrap \
        "${_milestones_dir}" >/dev/null 2>&1; then
        echo "FAILED: expected DevCloud setup admission acceptance!" >&2
        exit 1
    fi
}

expect_rejection() {
    local _milestones_dir="$1"

    if check_amd_devcloud_setup_admission_dont_wrap \
        "${_milestones_dir}" >/dev/null 2>&1; then
        echo "FAILED: expected DevCloud setup admission rejection!" >&2
        exit 1
    fi
}

BARE_DIR="${TEST_TMP_DIR}/bare"
UPGRADED_DIR="${TEST_TMP_DIR}/upgraded"
TMUX_ONLY_DIR="${TEST_TMP_DIR}/tmux-only"
PENDING_DIR="${TEST_TMP_DIR}/pending"
COMPLETED_DIR="${TEST_TMP_DIR}/completed"
MANAGED_DIR="${TEST_TMP_DIR}/managed"
EARLY_BOOTSTRAP_DIR="${TEST_TMP_DIR}/early-bootstrap"
DRIVER_INSTALLED_DIR="${TEST_TMP_DIR}/driver-installed"
DRIVER_PENDING_DIR="${TEST_TMP_DIR}/driver-pending"
DRIVER_COMPLETED_DIR="${TEST_TMP_DIR}/driver-completed"
EARLY_DRIVER_DIR="${TEST_TMP_DIR}/early-driver"
EARLY_DRIVER_REBOOT_DIR="${TEST_TMP_DIR}/early-driver-reboot"
CONTRADICTORY_DRIVER_REBOOT_DIR="${TEST_TMP_DIR}/contradictory-driver-reboot"
ROCM_USERLAND_DIR="${TEST_TMP_DIR}/rocm-userland"
EARLY_ROCM_USERLAND_DIR="${TEST_TMP_DIR}/early-rocm-userland"
POST_USERLAND_COMMON_DIR="${TEST_TMP_DIR}/post-userland-common"
CONTRADICTORY_DIR="${TEST_TMP_DIR}/contradictory"
BAD_MARKER_DIR="${TEST_TMP_DIR}/bad-marker"
BAD_MILESTONES_PATH="${TEST_TMP_DIR}/not-a-directory"
mkdir "${BARE_DIR}" "${UPGRADED_DIR}" "${TMUX_ONLY_DIR}" "${PENDING_DIR}" \
    "${COMPLETED_DIR}" "${CONTRADICTORY_DIR}" "${BAD_MARKER_DIR}"
mkdir "${MANAGED_DIR}" "${EARLY_BOOTSTRAP_DIR}" "${DRIVER_INSTALLED_DIR}" \
    "${DRIVER_PENDING_DIR}" "${DRIVER_COMPLETED_DIR}" \
    "${EARLY_DRIVER_DIR}" "${EARLY_DRIVER_REBOOT_DIR}" \
    "${CONTRADICTORY_DRIVER_REBOOT_DIR}" "${ROCM_USERLAND_DIR}" \
    "${EARLY_ROCM_USERLAND_DIR}" "${POST_USERLAND_COMMON_DIR}"
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

touch "${MANAGED_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
    "${MANAGED_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
    "${MANAGED_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done" \
    "${MANAGED_DIR}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME}.done"
reset_observations
set_repository_bootstrap_observations
expect_acceptance "${MANAGED_DIR}"

reset_observations
set_repository_bootstrap_observations
expect_rejection "${COMPLETED_DIR}"

reset_observations
set_repository_bootstrap_observations
TEST_PACKAGE_OUTPUT=$'amdgpu-install\tinstalled\tunexpected\n'
expect_rejection "${MANAGED_DIR}"

reset_observations
set_repository_bootstrap_observations
TEST_COMMAND_ARTIFACTS="amdgpu-install"
expect_rejection "${MANAGED_DIR}"

reset_observations
set_repository_bootstrap_observations
TEST_PATH_ARTIFACTS+=$'\n/opt/rocm'
expect_rejection "${MANAGED_DIR}"

reset_observations
expect_rejection "${MANAGED_DIR}"

for _driver_dir in "${DRIVER_INSTALLED_DIR}" "${DRIVER_PENDING_DIR}" \
    "${DRIVER_COMPLETED_DIR}"; do
    touch "${_driver_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
        "${_driver_dir}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
        "${_driver_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done" \
        "${_driver_dir}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME}.done" \
        "${_driver_dir}/${AMD_DEVCLOUD_DRIVER_STAGE_NAME}.done"
done
touch "${DRIVER_PENDING_DIR}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.pending"
touch "${DRIVER_COMPLETED_DIR}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.done"

reset_observations
set_driver_observations
expect_acceptance "${DRIVER_INSTALLED_DIR}"

reset_observations
set_driver_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
expect_acceptance "${DRIVER_PENDING_DIR}"

reset_observations
set_driver_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
TEST_COMMAND_ARTIFACTS+=$'\namd-smi'
expect_acceptance "${DRIVER_COMPLETED_DIR}"

reset_observations
set_driver_observations
expect_rejection "${DRIVER_COMPLETED_DIR}"

reset_observations
set_driver_observations
TEST_AMDGPU_LOADED=1
expect_rejection "${DRIVER_PENDING_DIR}"

reset_observations
set_driver_observations
TEST_PACKAGE_OUTPUT+=$'rocm\tinstalled\t7.2.3\n'
expect_rejection "${DRIVER_INSTALLED_DIR}"

reset_observations
set_driver_observations
TEST_ROCM_ALTERNATIVE_MATCHES=0
expect_rejection "${DRIVER_INSTALLED_DIR}"

touch "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
    "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
    "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done" \
    "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME}.done" \
    "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_DRIVER_STAGE_NAME}.done" \
    "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.done" \
    "${ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_ROCM_USERLAND_STAGE_NAME}.done"

reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
expect_acceptance "${ROCM_USERLAND_DIR}"

cp --archive "${ROCM_USERLAND_DIR}/." "${POST_USERLAND_COMMON_DIR}/"
touch "${POST_USERLAND_COMMON_DIR}/ensure_pinned_cmake.done" \
    "${POST_USERLAND_COMMON_DIR}/ensure_apt_with_custom_conf.done" \
    "${POST_USERLAND_COMMON_DIR}/ensure_base_dl_virtualenv.done"
reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
expect_acceptance "${POST_USERLAND_COMMON_DIR}"

reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
TEST_COMMAND_ARTIFACTS+=$'\namd-smi\nrocm-smi\nrocminfo\nhipconfig'
expect_acceptance "${ROCM_USERLAND_DIR}"

reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
expect_rejection "${DRIVER_COMPLETED_DIR}"

reset_observations
set_driver_observations
TEST_PACKAGE_OUTPUT+="${AMD_DEVCLOUD_ROCM_METAPACKAGE}"$'\tinstalled\tunexpected\n'
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
expect_rejection "${ROCM_USERLAND_DIR}"

reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
TEST_COMMAND_ARTIFACTS="rocminfo"
expect_rejection "${ROCM_USERLAND_DIR}"

reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
TEST_PACKAGE_OUTPUT+=$'rocm\tinstalled\t7.2.3\n'
expect_rejection "${ROCM_USERLAND_DIR}"

reset_observations
set_rocm_userland_observations
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1
TEST_ROCM_ALTERNATIVE_MATCHES=0
expect_rejection "${ROCM_USERLAND_DIR}"

touch "${EARLY_ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_DRIVER_STAGE_NAME}.done" \
    "${EARLY_ROCM_USERLAND_DIR}/${AMD_DEVCLOUD_ROCM_USERLAND_STAGE_NAME}.done"
reset_observations
set_rocm_userland_observations
expect_rejection "${EARLY_ROCM_USERLAND_DIR}"

touch "${EARLY_DRIVER_DIR}/${AMD_DEVCLOUD_DRIVER_STAGE_NAME}.done"
reset_observations
set_driver_observations
expect_rejection "${EARLY_DRIVER_DIR}"

touch "${EARLY_DRIVER_REBOOT_DIR}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.pending"
reset_observations
set_driver_observations
expect_rejection "${EARLY_DRIVER_REBOOT_DIR}"

touch \
    "${CONTRADICTORY_DRIVER_REBOOT_DIR}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.pending" \
    "${CONTRADICTORY_DRIVER_REBOOT_DIR}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.done"
reset_observations
expect_rejection "${CONTRADICTORY_DRIVER_REBOOT_DIR}"

touch "${EARLY_BOOTSTRAP_DIR}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done" \
    "${EARLY_BOOTSTRAP_DIR}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done" \
    "${EARLY_BOOTSTRAP_DIR}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME}.done"
reset_observations
set_repository_bootstrap_observations
expect_rejection "${EARLY_BOOTSTRAP_DIR}"

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
TEST_PACKAGE_OUTPUT=$'amdgpu-install\tinstalled\tunexpected\n'
expect_rejection "${BARE_DIR}"

reset_observations
TEST_PACKAGE_OUTPUT=$'rocm7.2.3\tconfig-files\t7.2.3\n'
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

echo "PASSED AMD DevCloud setup-admission tests!"
