#!/bin/bash

set -euo pipefail

CUPY_ENV_FLAG="--cupy-env-setup"
COMFYUI_FLAG="--comfyui-addons-setup"
FASTF_SETUP_FLAG="--fastfetch-setup"
DO_CUPY_ENV=0
DO_COMFYUI_ADDONS=0
DO_FASTFETCH=0

usage() {
    echo "Usage: $0 [$CUPY_ENV_FLAG] [$COMFYUI_FLAG] [$FASTF_SETUP_FLAG] [-h|--help]"
    exit 0
}

# Parse args
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    "$CUPY_ENV_FLAG") DO_CUPY_ENV=1; shift;;
    "$COMFYUI_FLAG") DO_COMFYUI_ADDONS=1; shift;;
    "$FASTF_SETUP_FLAG") DO_FASTFETCH=1; shift;;
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
source "../lib/azure_vars.sh"
source "../../common/lib/shared_vars.sh"
source "../../common/lib/util_funcs.sh"

echo "Please enter sudo password when prompted!"

# Ensure user access to GPU
ensure_groups_maybe_reboot_dont_wrap
# Environment assumptions check
ensure_basic_env_sanity_dont_wrap "${EXPECTED_DISTRO}" "${EXPECTED_DIST_VER}" \
                              "${EXPECTED_ROCM_VER}" "${EXPECTED_ROCMVER_REGEX}"


# Create directories containing idempotent milestone markers and logs
MILESTONES_DIR="$(realpath "${MILESTONES_DIR_RELPATH}")"
LOGS_DIR="$(realpath "${LOGS_DIR_RELPATH}")"
TEMP_DIR="$(realpath "${TEMP_DIR_RELPATH}")"
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
run_stage "$MILESTONES_DIR" ensure_oneapi_tbb_libs "${ONEAPI_TBB_PIN_VER}"
run_stage "$MILESTONES_DIR" ensure_apt_with_custom_conf \
    "${CURR_HOME_DIR}" "${APT_PKGS_LISTS_PATH}"

if (( DO_FASTFETCH )); then
    run_stage "$MILESTONES_DIR" ensure_github_fastfetch "${FASTFETCH_PIN_VER}" \
        "${FASTFETCH_DEB_FILENAME}" "${CURR_HOME_DIR}" "${TEMP_DIR}"
fi

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


# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
