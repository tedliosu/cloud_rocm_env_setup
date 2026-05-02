#!/bin/bash

set -euo pipefail

CHECK_CUPY_FLAG="--fail-on-no-cupy"
CHECK_COMFYUI_FLAG="--fail-on-no-comfyui"
CHECK_UFW_FLAG="--fail-on-no-ufw"
DO_CUPY_CHECK=0
DO_COMFYUI_CHECK=0
DO_UFW_CHECK=0

usage() {
    echo "Usage: $0 [$CHECK_CUPY_FLAG] [$CHECK_COMFYUI_FLAG] [$CHECK_UFW_FLAG] [-h|--help]"
    exit 0
}

# Parse args
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    "$CHECK_CUPY_FLAG") DO_CUPY_CHECK=1; shift;;
    "$CHECK_COMFYUI_FLAG") DO_COMFYUI_CHECK=1; shift;;
    "$CHECK_UFW_FLAG") DO_UFW_CHECK=1; shift;;
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
source "../../setup/common/lib/shared_vars.sh"
source "../lib/vald_shared_vars.sh"
source "../lib/vald_util_funcs.sh"

# Resolve real path of patches files/'lib' directory/etc.
LIB_DIR_ABS_PATH="$(realpath "${LIB_DIR_RELPATH}")"
TRITON_EXAMP_PATCH_PATH="$(realpath "${TRITON_EXAMPLE_PATCH_RELPATH}")"
HIPCO_BUILD_PATCH_PATH="$(realpath "${HIPCO_CMAKE_PATCH_RELPATH}")"
COMFYUI_WORKFLOW_PATH="$(realpath "${FLUX_1_DEV_WORKFLOW_RELPATH}")"


# BEGIN "MAIN"
_ACTIV_SRC_SCRIPT_RELPATH="bin/activate"
_HIPCC_INIT_SMOKE_EXE="hipcc_smoke"
_CHECKPOINTS_DIR_RELPATH="models/checkpoints"
_WORKFLOWS_DIR_RELPATH="user/default/workflows"
_CHECKPOINTS_INDIC_FILE="${_CHECKPOINTS_DIR_RELPATH}/put_checkpoints_here"
HCC_AMDGPU0_ARCH="$(rocm-smi --device 0 --showproductname --json 2>/dev/null | \
                         jq --raw-output '.card0."GFX Version"' | tr --delete "\n")" || {
    echo "FAILED to detect GFX Version of ROCm device 0!" >&2
    exit 1
}
env HIPCC_VERBOSE=7 hipcc --offload-arch="${HCC_AMDGPU0_ARCH}" \
    "${LIB_DIR_ABS_PATH}/basic_hipcc_prog_smoke.cpp" -o "./${_HIPCC_INIT_SMOKE_EXE}"
"./${_HIPCC_INIT_SMOKE_EXE}"
rm "./${_HIPCC_INIT_SMOKE_EXE}"
validate_basic_hipco "${CURR_HOME_DIR}/${HIPCO_REPO_LOCAL_DIRNAME}" \
    "${HIPCO_REPO_UPSTREAM_COMMIT}" "${HCC_AMDGPU0_ARCH}" "${HIPCO_BUILD_PATCH_PATH}"
if [[ ! -f "${DEEP_LEARN_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}" ]]; then
    echo "FAILED to detect deep learning base virtualenv!" >&2
    exit 1
fi
# Intentional variable path sourcing
# shellcheck disable=SC1091,SC1090
source "${DEEP_LEARN_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}"
python3 "${LIB_DIR_ABS_PATH}/torchcodec_cpu_abi_smoke.py"
python3 "${LIB_DIR_ABS_PATH}/torchvision_vit_resnet_abi_smoke.py"
validate_basic_triton "${CURR_HOME_DIR}/${TRITON_REPO_LOCAL_DIRNAME}" \
    "${TRITON_REPO_UPSTREAM_TAG}" "${TRITON_EXAMP_PATCH_PATH}"
deactivate
if [[ -f "${GPU_ARR_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}" ]]; then
    _ONEAPI_TBB_LIBPATHS="/opt/intel/oneapi/tbb/${ONEAPI_TBB_PIN_VER}/lib"
    _ONEAPI_TBB_LIBPATHS="${_ONEAPI_TBB_LIBPATHS}:/opt/intel/oneapi/tcm/${ONEAPI_TCM_PIN_VER}/lib"
    # shellcheck disable=SC1091,SC1090
    source "${GPU_ARR_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}"
    env CUPY_ACCELERATORS="cub" python3 "${LIB_DIR_ABS_PATH}/cupy_numpy_smoke.py"
    env LD_LIBRARY_PATH="${_ONEAPI_TBB_LIBPATHS}" python3 "${LIB_DIR_ABS_PATH}/numba_smoke.py"
    echo "NOTE: Numba test used LD_LIBRARY_PATH='${_ONEAPI_TBB_LIBPATHS}'"
    deactivate
elif (( DO_CUPY_CHECK )); then
    echo "FAILED to detect CuPy virtualenv," >&2
    echo "(${CHECK_CUPY_FLAG} flag detected)!" >&2
    exit 1
else
    echo "CuPy virtualenv and ${CHECK_CUPY_FLAG} flag both not detected,"
    echo "skipping associated validations..."
fi
if [[ -f "${COMFYUI_REPO_LOCAL_DIR}/${_CHECKPOINTS_INDIC_FILE}" ]]; then
    _MODEL_FILENAME="$(jq --raw-output "${COMFYUI_WORKFLOW_MODLNAME_FILTER}" \
                                                       "${COMFYUI_WORKFLOW_PATH}")" || {
        echo "FAILED to parse ComfyUI workflow JSON" \
             "for model checkpoint filename!" >&2
        exit 1
    }
    _WORKFLOW_FILENAME="$(basename "${COMFYUI_WORKFLOW_PATH}")"
    mkdir --parent "${COMFYUI_REPO_LOCAL_DIR}/${_WORKFLOWS_DIR_RELPATH}"
    # the rm's make this script reentrant; redownloading/recopying here is always OK
    rm --force "${COMFYUI_REPO_LOCAL_DIR}/${_CHECKPOINTS_DIR_RELPATH}/${_MODEL_FILENAME}"
    rm --force "${COMFYUI_REPO_LOCAL_DIR}/${_WORKFLOWS_DIR_RELPATH}/${_WORKFLOW_FILENAME}"
    # shellcheck disable=SC1091,SC1090
    source "${DEEP_LEARN_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}"
    hf download --repo-type "${COMFYUI_VALD_MODEL_REPO_TYPE}" \
                --revision "${COMFYUI_VALD_MODEL_REPO_COMMIT}" \
                --local-dir "${COMFYUI_REPO_LOCAL_DIR}/${_CHECKPOINTS_DIR_RELPATH}" \
                "${COMFYUI_VALD_MODEL_REPO_RELPATH}" "${_MODEL_FILENAME}"
    deactivate
    cp --target-directory="${COMFYUI_REPO_LOCAL_DIR}/${_WORKFLOWS_DIR_RELPATH}" \
                                                           "${COMFYUI_WORKFLOW_PATH}"
    echo "PASS: ComfyUI FLUX.1 [dev] FP8 assets and workflow ready for manual validation!"
    echo "Please ensure that you have an ssh instance that port-forwards 8188"
    echo "from the remote VM to your local computer that you're accessing the"
    echo "remote VM from, and then run the following commands in the following"
    echo "order to launch ComfyUI:"
    echo "    1. source ${DEEP_LEARN_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}"
    echo "    2. cd ${COMFYUI_REPO_LOCAL_DIR}"
    echo "    3. python3 main.py --disable-auto-launch" \
                 "--disable-xformers --disable-dynamic-vram"
    echo "Then, follow the instructions specified to:"
    echo "    1. Access the web UI of the ComfyUI instance that you just launched"
    echo "    2. Load in the web UI the workflow stored at:"
    echo "       '${COMFYUI_WORKFLOW_PATH}'"
    echo "    2. Run validation smoke tests within the Web UI."
elif (( DO_COMFYUI_CHECK )); then
    echo "FAILED to detect local ComfyUI cloned repository," >&2
    echo "(${CHECK_COMFYUI_FLAG} flag detected)!" >&2
    exit 1
else
    echo "local ComfyUI cloned repostiory and" \
        "${CHECK_COMFYUI_FLAG} flag both not detected,"
    echo "skipping associated validations..."
fi
if which ufw >/dev/null; then
    echo "Please enter sudo password when prompted!"
    UFW_STATUS_OUTPUT="$(sudo --set-home ufw status)" || {
        echo "FAILURE: 'ufw status' command returned non-zero exit code!" >&2
        exit 1
    }
    if echo "$UFW_STATUS_OUTPUT" | \
        grep --ignore-case --extended-regexp --quiet "status.+active"; then
        echo "$UFW_STATUS_OUTPUT"
        echo "PASS active 'ufw' check!"
    else
        echo "WARNING: 'ufw' installed but no active 'ufw' detected! instead got:"
        echo "$UFW_STATUS_OUTPUT"
        echo "if this was unintended, please run the following commands in the"
        echo "    following order if applicable (without the single quotes):"
        echo "    1. 'sudo -H ufw default deny incoming'"
        echo "    2. 'sudo -H ufw default allow outgoing'"
        echo "    3. 'sudo -H ufw allow ssh'"
        echo "    4. 'sudo -H ufw enable'"
    fi
elif (( DO_UFW_CHECK )); then
    echo "FAILED to detect a working ufw installation," >&2
    echo "(${CHECK_UFW_FLAG} flag detected)!" >&2
    exit 1
else
    echo "'ufw' binary and ${CHECK_UFW_FLAG} flag both not detected,"
    echo "skipping associated validations..."
fi


# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
