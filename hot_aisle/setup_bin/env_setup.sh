#!/bin/bash

set -euo pipefail

# Arguments parsing
# TODO

# Enforce CWD is the directory that this script resides in
OLD_CWDIR="$(pwd -P)" || {
    echo "Failed to resolve initial directory path" >&2
    exit 1
}
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" || {
    echo "Failed to cd into script directory: $SCRIPT_DIR (real path '$(realpath "$SCRIPT_DIR")')" >&2
    exit 1
}

# Now we source all needed common functions/variables/etc.
source "../vars.sh"
source "../../common/lib/util_funcs.sh"

# Environment assumptions check specific to hot aisle invariants
if ! grep --quiet "DISTRIB_ID=${EXPECTED_DISTRO}" /etc/lsb-release ||
   ! grep --quiet "DISTRIB_RELEASE=${EXPECTED_DIST_VER}" /etc/lsb-release; then
    echo -e "Got unexpected '/etc/lsb-release' with contents:\n$(cat /etc/lsb-release)" >&2
    echo -e "\n    This IS NOT ${EXPECTED_DISTRO} ${EXPECTED_DIST_VER}; bailing!" >&2
    exit 1
fi
if rocminfo | grep --ignore-case --quiet "NOT loaded"; then
    echo "amdgpu dkms not installed; bailing!" >&2
    exit 1
fi
ROCM_DETECTED_VER="$(hipconfig --rocmpath | cut -d"-" -f2)"
if [[ ! "$ROCM_DETECTED_VER" =~ $EXPECTED_ROCMVER_REGEX ]]; then
    echo "'hipconfig' reports ROCm userland version $ROCM_DETECTED_VER!" >&2
    echo -e "\n    Please update all environment setup logic and configs" >&2
    echo -e "\n    before rerunning this script, as assumed version is" >&2
    echo " ${EXPECTED_ROCM_VER}!"
    exit 1
fi

echo "Please enter sudo password when prompted!"

# Create directory containing idempotent milestone markers
MILESTONES_DIR="$(realpath "../state_trackers")"
mkdir --parents "$MILESTONES_DIR"
# Directory containing packages to be setup lists
PKGS_LISTS_DIR="$(realpath "../../common/etc")"


# BEGIN "MAIN"
run_stage "$MILESTONES_DIR" apt_get_sys_update
reboot_once_dont_wrap "$MILESTONES_DIR"
run_stage "$MILESTONES_DIR" ensure_latest_cmake "${EXPECTED_DIST_CODENAME}"
run_stage "$MILESTONES_DIR" ensure_apt_with_custom_conf "${PKGS_LISTS_DIR}"


# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
