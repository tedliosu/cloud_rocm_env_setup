#!/bin/bash

set -euo pipefail

EXPECTED_DISTRO="Ubuntu"
EXPECTED_DIST_VER="22.04"
EXPECTED_ROCM_VER="7.2"
EXPECTED_ROCMVER_REGEX="${EXPECTED_ROCM_VER/\./\\.}\.[0-9]+"

# Environment assumptions check specific to hot aisle invariants
if ! grep --quiet "DISTRIB_ID=${EXPECTED_DISTRO}" /etc/lsb-release ||
   ! grep --quiet "DISTRIB_RELEASE=${EXPECTED_DIST_VER}" /etc/lsb-release; then
    echo -e "Got unexpected '/etc/lsb-release' with contents:\n$(cat /etc/lsb-release)" >&2
    echo -e "\n    This IS NOT ${EXPECTED_DISTRO} ${EXPECTED_DIST_VER}; bailing!" >&2
    exit 1
fi
if ! dkms status amdgpu | grep --quiet installed; then
    echo "Out of tree amdgpu dkms not installed; bailing!" >&2
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

# Enforce CWD is the directory that this script resides in
OLD_CWDIR="$(pwd -P)" || {
    echo "Failed to resolve initial directory path" >&2
    exit 1
}
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR" || {
    echo "Failed to cd into script directory: $SCRIPT_DIR" >&2
    exit 1
}
SCRIPT_ABS_DIR="$(pwd -P)" || {
    echo "Failed to resolve script directory path" >&2
    exit 1
}

# Create directory containing idempotent milestone markers
MILESTONES_DIR="$(realpath "${SCRIPT_ABS_DIR}/../state_trackers")"
mkdir --parents "$MILESTONES_DIR"

# Helper function to run a stage
# Usage: run_stage <function_to_run>
run_stage() {

    local func_to_run="$1"
    local done_marker_file="$MILESTONES_DIR/${func_to_run}.done"

    if [[ ! -f "$done_marker_file" ]]; then
        echo "--- starting stage: $func_to_run ---"
        "$func_to_run" && touch "$done_marker_file"
        echo "--- completed stage: $func_to_run ---"
    else
        echo "--- skipping stage: $func_to_run (already complete) ---"
    fi

}

# System update (no kernel update by default)
apt_get_sys_update() {
    sudo --set-home apt-get update
    sudo --set-home apt-get upgrade --assume-yes
}

# Reboot once helper (for ONLY after a system update)
reboot_once_dont_wrap() {
    local reboot_marker_file="$MILESTONES_DIR/${FUNCNAME[0]}.done"
    if [[ ! -f "$reboot_marker_file" ]]; then
        echo "Reboot required, performing ONE reboot..."
        touch "$reboot_marker_file"
        sudo --set-home reboot
        exit 0
    else
        echo "--- skipping stage: ${FUNCNAME[0]} (already complete) ---"
    fi
}

# BEGIN "MAIN"
run_stage apt_get_sys_update
reboot_once_dont_wrap

# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
