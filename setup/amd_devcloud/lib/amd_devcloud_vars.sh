# shellcheck shell=bash
# This file is sourced by provider scripts; standalone analysis cannot see its
#     consumers.
# shellcheck disable=SC2034

readonly AMD_DEVCLOUD_REQUIRED_GROUPS=(adm video render)
readonly AMD_DEVCLOUD_TARGET_HOME_PARENT="/home"
readonly AMD_DEVCLOUD_TARGET_LOGIN_SHELL="/bin/bash"
readonly AMD_DEVCLOUD_SUDOERS_DIR="/etc/sudoers.d"
readonly AMD_DEVCLOUD_SUDOERS_FILE_PREFIX="cloud_rocm_env_setup-amd-devcloud-"
# An invalid '*' hash disables Unix-password matching without Linux OpenSSH's
#     leading-'!' whole-account rejection when PAM is disabled.
readonly AMD_DEVCLOUD_DISABLED_PASSWORD_FIELD='*'
readonly AMD_DEVCLOUD_SUDOERS_POLICY_SUFFIX='ALL=(ALL:ALL) NOPASSWD: ALL'
# Match the C-locale sudo-list representation of the selected sudoers policy.
readonly AMD_DEVCLOUD_SUDO_LIST_POLICY_REGEX='^[[:blank:]]*\(ALL[[:blank:]]*:[[:blank:]]*ALL\)[[:blank:]]+NOPASSWD:[[:blank:]]+ALL$'

readonly AMD_DEVCLOUD_EXPECTED_DISTRO_ID="ubuntu"
readonly AMD_DEVCLOUD_EXPECTED_DISTRO_NAME="Ubuntu"
readonly AMD_DEVCLOUD_EXPECTED_DISTRO_VERSION="24.04"
readonly AMD_DEVCLOUD_EXPECTED_BARE_PCI_DEVICE_ID="1002:74b5"

readonly AMD_DEVCLOUD_ADMISSION_BARE="AMD_DEVCLOUD_BARE"
readonly AMD_DEVCLOUD_ADMISSION_PACKAGE_SENTINELS=(
    amdgpu-install
    amdgpu-dkms
    rocm
    rocm7.2.3
)
readonly AMD_DEVCLOUD_ADMISSION_COMMAND_SENTINELS=(
    amdgpu-install
    amdgpu-setup
    amd-smi
    rocm-smi
    rocminfo
    hipconfig
)
readonly AMD_DEVCLOUD_ADMISSION_PATH_SENTINELS=(
    /etc/amdgpu-install/amdgpu-setup.conf
    /etc/apt/keyrings/rocm.gpg
    /etc/apt/preferences.d/repo-radeon-pin-600
    /etc/apt/sources.list.d/amdgpu.list
    /etc/apt/sources.list.d/amdgpu-proprietary.list
    /etc/apt/sources.list.d/rocm.list
    /usr/bin/amdgpu-install
    /usr/bin/amdgpu-setup
    /opt/rocm
    /opt/rocm-7.2.3
)

readonly AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME="apt_get_sys_update"
readonly AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME="amd_devcloud_system_upgrade_reboot"
