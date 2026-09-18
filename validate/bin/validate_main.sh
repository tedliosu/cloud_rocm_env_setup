#!/bin/bash

set -euo pipefail

REQUIRE_SOURCE_BUILT_CUPY_ENV_FLAG="--fail-on-no-source-built-cupy-env"
REQUIRE_PACKAGED_AMD_RAPIDS_ENV_FLAG="--fail-on-no-packaged-amd-rapids-env"
CHECK_COMFYUI_FLAG="--fail-on-no-comfyui"
SKIP_UFW_CHECKS_FLAG="--skip-ufw-checks"
RELAX_UFW_CHECKS_FLAG="--relax-ufw-checks"
REQUIRE_SOURCE_BUILT_CUPY_ENV=0
REQUIRE_PACKAGED_AMD_RAPIDS_ENV=0
DO_COMFYUI_CHECK=0
DO_UFW_CHECK=1
STRICT_UFW_CHECK=1

usage() {
    echo -n "Usage: $0 [$REQUIRE_SOURCE_BUILT_CUPY_ENV_FLAG] "
    echo -n "[$REQUIRE_PACKAGED_AMD_RAPIDS_ENV_FLAG] [$CHECK_COMFYUI_FLAG] "
    echo "[$SKIP_UFW_CHECKS_FLAG|$RELAX_UFW_CHECKS_FLAG] [-h|--help]"
    echo "NOTE: $SKIP_UFW_CHECKS_FLAG and $RELAX_UFW_CHECKS_FLAG are mutually exclusive"
}

# Parse args
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    "$REQUIRE_SOURCE_BUILT_CUPY_ENV_FLAG") REQUIRE_SOURCE_BUILT_CUPY_ENV=1; shift;;
    "$REQUIRE_PACKAGED_AMD_RAPIDS_ENV_FLAG") REQUIRE_PACKAGED_AMD_RAPIDS_ENV=1; shift;;
    "$CHECK_COMFYUI_FLAG") DO_COMFYUI_CHECK=1; shift;;
    "$SKIP_UFW_CHECKS_FLAG") DO_UFW_CHECK=0; shift;;
    "$RELAX_UFW_CHECKS_FLAG") STRICT_UFW_CHECK=0; shift;;
    -h|--help) usage; exit 0;;
    *) usage; exit 1;;
  esac
done

if (( ! DO_UFW_CHECK && ! STRICT_UFW_CHECK )); then
    echo "ERROR: $SKIP_UFW_CHECKS_FLAG and $RELAX_UFW_CHECKS_FLAG are mutually exclusive" >&2
    usage
    exit 1
fi

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
LIBHIPCXX_PIN_PATCH_PATH="$(realpath "${ROCM_DS_CMAKE_HIPCXX_PATCH_RELPATH}")"
COMFYUI_WORKFLOW_PATH="$(realpath "${FLUX_1_DEV_WORKFLOW_RELPATH}")"


# BEGIN "MAIN"
if [[ -n "${HSA_OVERRIDE_GFX_VERSION:-}" ]]; then
    echo "ERROR: HSA_OVERRIDE_GFX_VERSION='${HSA_OVERRIDE_GFX_VERSION}' is set!" >&2
    echo "    The main validator supports only native baseline validation." >&2
    echo "    Unset the override before rerunning this script." >&2
    echo "    Run 'cupy_numpy_smoke.py' directly for a user-controlled" >&2
    echo "    override-assisted CuPy experiment." >&2
    exit 1
fi
if ! command -v hipconfig >/dev/null 2>&1; then
    echo "ERROR: unable to find hipconfig through PATH!" >&2
    exit 1
fi
if ! ROCM_PATH_SELECTED_ROOT="$(hipconfig --rocmpath)"; then
    echo "ERROR: hipconfig --rocmpath failed!" >&2
    exit 1
fi
if ! ROCM_HOME="$(canonicalize_rocm_validation_root \
    "${ROCM_PATH_SELECTED_ROOT}")"; then
    exit 1
fi
LD_LIBRARY_PATH="${ROCM_HOME}/lib"
export ROCM_HOME LD_LIBRARY_PATH
echo "Validator PATH-selected ROCm root: ${ROCM_PATH_SELECTED_ROOT}"
echo "Validator canonical ROCM_HOME: ${ROCM_HOME}"
echo "Validator-scoped LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"
if (( DO_UFW_CHECK )); then
    echo "Please enter sudo password when prompted!"
    validate_ufw_config "${STRICT_UFW_CHECK}"
fi
_ACTIV_SRC_SCRIPT_RELPATH="bin/activate"
_HIPCC_INIT_SMOKE_EXE="hipcc_smoke"
_CHECKPOINTS_DIR_RELPATH="models/checkpoints"
_WORKFLOWS_DIR_RELPATH="user/default/workflows"
_CHECKPOINTS_INDIC_FILE="${_CHECKPOINTS_DIR_RELPATH}/put_checkpoints_here"
HCC_AMDGPU0_ARCH="$(detect_amd_smi_gpu_arch 0)" || {
    echo "FAILED to detect GFX Version of ROCm device 0!" >&2
    exit 1
}
env HIPCC_VERBOSE=7 hipcc --offload-arch="${HCC_AMDGPU0_ARCH}" \
    "${LIB_DIR_ABS_PATH}/basic_hipcc_prog_smoke.cpp" -o "./${_HIPCC_INIT_SMOKE_EXE}"
"./${_HIPCC_INIT_SMOKE_EXE}"
rm "./${_HIPCC_INIT_SMOKE_EXE}"
validate_basic_hipco "${CURR_HOME_DIR}/${HIPCO_REPO_LOCAL_DIRNAME}" \
    "${HIPCO_REPO_UPSTREAM_COMMIT}" "${HCC_AMDGPU0_ARCH}" "${HIPCO_BUILD_PATCH_PATH}" \
    "${CURR_HOME_DIR}/${ROCM_DS_CMAKE_REPO_LOCAL_DIRNAME}" "${ROCM_DS_CMAKE_REPO_UPSTREAM_COMMIT}" \
    "${LIBHIPCXX_PIN_PATCH_PATH}" "${ROCM_HOME}"
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
_ONEAPI_TBB_LIBPATHS="/opt/intel/oneapi/tbb/${ONEAPI_TBB_PIN_VER}/lib"
_ONEAPI_TBB_LIBPATHS="${_ONEAPI_TBB_LIBPATHS}:/opt/intel/oneapi/tcm/${ONEAPI_TCM_PIN_VER}/lib"
_NUMBA_LIBRARY_PATHS="${_ONEAPI_TBB_LIBPATHS}:${LD_LIBRARY_PATH}"
validate_source_built_cupy_env "${GPU_ARR_VIRTENV_DIR}" \
    "${_ACTIV_SRC_SCRIPT_RELPATH}" "${LIB_DIR_ABS_PATH}" \
    "${_NUMBA_LIBRARY_PATHS}" "${REQUIRE_SOURCE_BUILT_CUPY_ENV}" \
    "${REQUIRE_SOURCE_BUILT_CUPY_ENV_FLAG}"
validate_packaged_amd_rapids_env "${PACKAGED_AMD_RAPIDS_VIRTENV_DIR}" \
    "${_ACTIV_SRC_SCRIPT_RELPATH}" "${LIB_DIR_ABS_PATH}" "${ROCM_HOME}" \
    "${_NUMBA_LIBRARY_PATHS}" "${REQUIRE_PACKAGED_AMD_RAPIDS_ENV}" \
    "${REQUIRE_PACKAGED_AMD_RAPIDS_ENV_FLAG}" \
    "${HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT}"
if [[ -f "${COMFYUI_REPO_LOCAL_DIR}/${_CHECKPOINTS_INDIC_FILE}" ]]; then
    _MODEL_FILENAME="$(jq --raw-output "${COMFYUI_WORKFLOW_MODLNAME_FILTER}" \
                                                       "${COMFYUI_WORKFLOW_PATH}")" || {
        echo "FAILED to parse ComfyUI workflow JSON" \
             "for model checkpoint filename!" >&2
        exit 1
    }
    if ! is_plain_filename "${_MODEL_FILENAME}"; then
        echo "FAILED: ComfyUI workflow must select exactly one plain" >&2
        echo "    model checkpoint filename, not a path or list!" >&2
        exit 1
    fi
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


# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
