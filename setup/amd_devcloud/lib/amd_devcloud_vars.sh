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
readonly AMD_DEVCLOUD_EXPECTED_GPU_INDEX="0"
readonly AMD_DEVCLOUD_EXPECTED_GPU_MARKET_NAME="AMD Instinct MI300X VF"
readonly AMD_DEVCLOUD_EXPECTED_GPU_ARCH="gfx942"
readonly AMD_DEVCLOUD_EXPECTED_DKMS_ARCH="x86_64"

readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL="https://repo.radeon.com/amdgpu-install/7.2.3/ubuntu/noble/amdgpu-install_7.2.3.70203-1_all.deb"
readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_FILENAME="amdgpu-install_7.2.3.70203-1_all.deb"
readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_SHA256="15606d326bd6d8a0a6c467625cb50c45fa6ecebcf483db04da911efe57b933d9"
readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION="30.30.3.0.30300300-2327507.24.04"
readonly AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH="/opt/rocm"
readonly AMD_DEVCLOUD_ROCM_VERSIONED_ROOT="/opt/rocm-7.2.3"
readonly AMD_DEVCLOUD_ROCM_VERSIONED_BIN="${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}/bin"
readonly AMD_DEVCLOUD_ROCM_VERSIONED_LIBRARY_DIR="${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}/lib"
readonly AMD_DEVCLOUD_ROCM_PROFILE_BEGIN_MARKER="# BEGIN cloud_rocm_env_setup AMD DevCloud ROCm PATH"
readonly AMD_DEVCLOUD_ROCM_PROFILE_END_MARKER="# END cloud_rocm_env_setup AMD DevCloud ROCm PATH"
readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_COMMAND_ARTIFACTS=(
    amdgpu-install
    amdgpu-setup
)
readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PATH_ARTIFACTS=(
    /etc/amdgpu-install/amdgpu-setup.conf
    /etc/apt/keyrings/rocm.gpg
    /etc/apt/preferences.d/repo-radeon-pin-600
    /etc/apt/sources.list.d/amdgpu.list
    /etc/apt/sources.list.d/amdgpu-proprietary.list
    /etc/apt/sources.list.d/rocm.list
    /usr/bin/amdgpu-install
    /usr/bin/amdgpu-setup
)

readonly AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE="amdgpu-dkms"
readonly AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION="1:6.16.13.30300300-2327507.24.04"
readonly AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION="6.16.13-2327507.24.04"
readonly AMD_DEVCLOUD_AMD_SMI_PACKAGE="amd-smi-lib7.2.3"
readonly AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION="26.2.2.70203-90~24.04"
readonly AMD_DEVCLOUD_AMD_SMI_PATH="${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}/bin/amd-smi"
readonly AMD_DEVCLOUD_EXPECTED_AMD_SMI_DRIVER_VERSION="6.16.13"
readonly AMD_DEVCLOUD_ROCM_CORE_PACKAGE="rocm-core7.2.3"
readonly AMD_DEVCLOUD_ROCM_CORE_PACKAGE_VERSION="7.2.3.70203-90~24.04"
readonly AMD_DEVCLOUD_ROCM_METAPACKAGE="rocm7.2.3"
readonly AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION="7.2.3.70203-90~24.04"
readonly AMD_DEVCLOUD_DRIVER_PATH_ARTIFACTS=(
    "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PATH_ARTIFACTS[@]}"
    "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}"
    "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}"
)

readonly AMD_DEVCLOUD_ADMISSION_BARE="AMD_DEVCLOUD_BARE"
readonly AMD_DEVCLOUD_ADMISSION_REPOSITORY_BOOTSTRAP="AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP"
readonly AMD_DEVCLOUD_ADMISSION_DRIVER_INSTALLED="AMD_DEVCLOUD_DRIVER_INSTALLED"
readonly AMD_DEVCLOUD_ADMISSION_ROCM_USERLAND_INSTALLED="AMD_DEVCLOUD_ROCM_USERLAND_INSTALLED"
readonly AMD_DEVCLOUD_ADMISSION_PACKAGE_SENTINELS=(
    amdgpu-install
    "${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}"
    "${AMD_DEVCLOUD_AMD_SMI_PACKAGE}"
    rocm
    "${AMD_DEVCLOUD_ROCM_CORE_PACKAGE}"
    "${AMD_DEVCLOUD_ROCM_METAPACKAGE}"
)
readonly AMD_DEVCLOUD_ADMISSION_COMMAND_SENTINELS=(
    "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_COMMAND_ARTIFACTS[@]}"
    amd-smi
    rocm-smi
    rocminfo
    hipconfig
)
readonly AMD_DEVCLOUD_ADMISSION_PATH_SENTINELS=(
    "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PATH_ARTIFACTS[@]}"
    "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}"
    "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}"
)

readonly AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME="apt_get_sys_update"
readonly AMD_DEVCLOUD_TMUX_STAGE_NAME="ensure_tmux"
readonly AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME="amd_devcloud_system_upgrade_reboot"
readonly AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME="install_amd_devcloud_repository_bootstrap"
readonly AMD_DEVCLOUD_DRIVER_STAGE_NAME="install_amd_devcloud_driver"
readonly AMD_DEVCLOUD_DRIVER_REBOOT_NAME="amd_devcloud_driver_reboot"
readonly AMD_DEVCLOUD_ROCM_USERLAND_STAGE_NAME="install_amd_devcloud_rocm_userland"
