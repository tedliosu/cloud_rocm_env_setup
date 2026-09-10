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
