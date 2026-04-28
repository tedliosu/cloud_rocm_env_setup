#!/bin/bash

set -euo pipefail

CHECK_CUPY_FLAG="--fail-on-no-cupy"
DO_CUPY_CHECK=0

usage() {
    echo "Usage: $0 [$CHECK_CUPY_FLAG] [-h|--help]"
    exit 0
}

# Parse args
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    "$CHECK_CUPY_FLAG") DO_CUPY_CHECK=1; shift;;
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


# BEGIN "MAIN"
_ACTIV_SRC_SCRIPT_RELPATH="bin/activate"
_HIPCC_INIT_SMOKE_EXE="hipcc_smoke"
HCC_AMDGPU0_ARCH="$(rocm-smi --device 0 --showproductname --json 2>/dev/null | \
                         jq --raw-output '.card0."GFX Version"' | tr --delete "\n")" || {
    echo "FAILED to detect GFX Version of ROCm device 0!" >&2
    exit 1
}
hipcc --offload-arch="${HCC_AMDGPU0_ARCH}" \
    "${LIB_DIR_ABS_PATH}/basic_hipcc_prog_smoke.cpp" -o "./${_HIPCC_INIT_SMOKE_EXE}"
"./${_HIPCC_INIT_SMOKE_EXE}"
rm "./${_HIPCC_INIT_SMOKE_EXE}"
validate_basic_hipco "${CURR_HOME_DIR}/${HIPCO_REPO_LOCAL_DIRNAME}" \
    "${HIPCO_REPO_UPSTREAM_COMMIT}" "${HCC_AMDGPU0_ARCH}"
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
    # shellcheck disable=SC1091,SC1090
    source "${GPU_ARR_VIRTENV_DIR}/${_ACTIV_SRC_SCRIPT_RELPATH}"
    env CUPY_ACCELERATORS="cub" python3 "${LIB_DIR_ABS_PATH}/cupy_numpy_smoke.py"
    deactivate
elif (( DO_CUPY_CHECK )); then
    echo "FAILED to detect CuPy virtualenv " >&2
    echo "(${CHECK_CUPY_FLAG} flag detected)!" >&2
    exit 1
else
    echo "CuPy virtualenv and ${CHECK_CUPY_FLAG} flag both not detected, "
    echo "skipping associated validations..."
fi


# Change back into old CWD just in case
cd "$OLD_CWDIR" || {
    echo "Failed to cd into initial directory: $OLD_CWDIR" >&2
    exit 1
}
