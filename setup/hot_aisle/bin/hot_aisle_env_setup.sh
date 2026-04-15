#!/bin/bash

set -euo pipefail

CUPY_ENV_FLAG="--cupy-env-setup"
COMFYUI_FLAG="--comfyui-addons-setup"
OLLAMA_FLAG="--ollama-runtime-setup"
DO_CUPY_ENV=0
DO_COMFYUI_ADDONS=0
DO_OLLAMA_RUNTIME=0

usage() {
    echo "Usage: $0 [$CUPY_ENV_FLAG] [$COMFYUI_FLAG] [$OLLAMA_FLAG] [-h|--help]"
    exit 0
}

# Parse args
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    "$CUPY_ENV_FLAG") DO_CUPY_ENV=1; shift;;
    "$COMFYUI_FLAG") DO_COMFYUI_ADDONS=1; shift;;
    "$OLLAMA_FLAG") DO_OLLAMA_RUNTIME=1; shift;;
    -h|--help) usage;;
    *) usage;;
  esac
done

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
source "../lib/hot_aisle_vars.sh"
source "../../common/lib/shared_vars.sh"
source "../../common/lib/util_funcs.sh"

# Environment assumptions check specific to hot aisle invariants
if ! grep --quiet "DISTRIB_ID=${EXPECTED_DISTRO}" /etc/lsb-release ||
   ! grep --quiet "DISTRIB_RELEASE=${EXPECTED_DIST_VER}" /etc/lsb-release; then
    echo -e "Got unexpected '/etc/lsb-release' with contents:\n$(cat /etc/lsb-release)" >&2
    echo -e "\n    This IS NOT ${EXPECTED_DISTRO} ${EXPECTED_DIST_VER}; bailing!" >&2
    exit 1
fi
if rocminfo | grep --ignore-case --quiet "NOT loaded"; then
    echo "amdgpu dkms not detected; bailing!" >&2
    exit 1
fi
ROCM_DETECTED_VER="$(hipconfig --rocmpath | cut -d"-" -f2)"
if [[ ! "$ROCM_DETECTED_VER" =~ $EXPECTED_ROCMVER_REGEX ]]; then
    echo "'hipconfig' reports ROCm userland version $ROCM_DETECTED_VER!" >&2
    echo -e "\n    Please update all environment setup logic and configs" >&2
    echo -e "\n    before rerunning this script, as assumed version is" >&2
    echo " ~${EXPECTED_ROCM_VER}!"
    exit 1
fi

echo "Please enter sudo password when prompted!"

# Create directories containing idempotent milestone markers and logs
MILESTONES_DIR="$(realpath "${MILESTONES_DIR_RELPATH}")"
LOGS_DIR="$(realpath "${LOGS_DIR_RELPATH}")"
mkdir --parents "$MILESTONES_DIR"
mkdir --parents "$LOGS_DIR"
# Resolve real path of packages-list files
APT_PKGS_LISTS_PATH="$(realpath "${APT_ONLY_REQS_TXT_RELPATH}")"
TORCH_PYPKGS_LISTS_PATH="$(realpath "${TORCH_ONLY_REQS_TXT_RELPATH}")"
NON_TORCH_DL_PYPKGS_LISTS_PATH="$(realpath "${NON_TORCH_REQS_TXT_RELPATH}")"
GPU_ARR_PYPKGS_LISTS_PATH="$(realpath "${GPU_ARR_REQS_TXT_RELPATH}")"
BEFORE_COMFYUI_LOG_PATH="$(realpath "${PRE_COMFYUI_PIP_FREEZE_RECS}")"
AFTER_COMFYUI_LOG_PATH="$(realpath "${POST_COMFYUI_PIP_FREEZE_RECS}")"


# BEGIN "MAIN"
run_stage "$MILESTONES_DIR" apt_get_sys_update
reboot_once_dont_wrap "$MILESTONES_DIR"
run_stage "$MILESTONES_DIR" ensure_latest_cmake "${EXPECTED_DIST_CODENAME}"
run_stage "$MILESTONES_DIR" ensure_apt_with_custom_conf \
    "${CURR_HOME_DIR}" "${APT_PKGS_LISTS_PATH}"
run_stage "$MILESTONES_DIR" ensure_base_dl_virtualenv "${DEEP_LEARN_VIRTENV_DIR}" \
    "${EXPECTED_ROCM_VER}" "${TORCH_PYPKGS_LISTS_PATH}" \
    "${NON_TORCH_DL_PYPKGS_LISTS_PATH}" "${TORCHCODEC_PIN_VER}"

if (( DO_CUPY_ENV )); then
    run_stage "$MILESTONES_DIR" ensure_gpu_arr_virtualenv "${GPU_ARR_VIRTENV_DIR}" \
        "${CUPY_REPO_LOCAL_DIR}" "${GPU_ARR_PYPKGS_LISTS_PATH}"
fi

if (( DO_COMFYUI_ADDONS )); then
    run_stage "$MILESTONES_DIR" ensure_comfyui_virtualenv "${DEEP_LEARN_VIRTENV_DIR}" \
        "${COMFYUI_REPO_LOCAL_DIR}" "${COMFYUI_PIN_VER_TAG}" "${TORCH_PYPKGS_LISTS_PATH}" \
        "${NON_TORCH_DL_PYPKGS_LISTS_PATH}" "${BEFORE_COMFYUI_LOG_PATH}" "${AFTER_COMFYUI_LOG_PATH}"
fi

# TODO: Remove this following line of code when all variables have been used
echo "OLLAMA: $DO_OLLAMA_RUNTIME"


# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
