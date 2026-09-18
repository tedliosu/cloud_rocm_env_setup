
# shellcheck shell=bash
# This file is sourced by the validation entry script; standalone analysis
#     cannot see its consumer.
# shellcheck disable=SC2034

readonly TRITON_REPO_LOCAL_DIRNAME="local_triton_repo"
readonly HIPCO_REPO_LOCAL_DIRNAME="local_hipco_repo"
readonly ROCM_DS_CMAKE_REPO_LOCAL_DIRNAME="local_rocm_ds_cmake_vald_repo"
readonly LIB_DIR_RELPATH="../lib"
_PATCHES_DIR_RELPATH="${LIB_DIR_RELPATH}/patches"
_VALD_ETC_DIR_RELPATH="../etc"
readonly TRITON_EXAMPLE_PATCH_RELPATH="${_PATCHES_DIR_RELPATH}/triton-no-plot-headless.patch"
readonly HIPCO_CMAKE_PATCH_RELPATH="${_PATCHES_DIR_RELPATH}/hipcollections-enable-gfx1101.patch"
readonly ROCM_DS_CMAKE_HIPCXX_PATCH_RELPATH="${_PATCHES_DIR_RELPATH}/rocm-ds-cmake-libhipcxx-pin.patch"
readonly FLUX_1_DEV_WORKFLOW_RELPATH="${_VALD_ETC_DIR_RELPATH}/flux_dev_checkpoint_example_tiled_vae_mod.json"

readonly TRITON_REPO_UPSTREAM_TAG="v3.6.0"
readonly HIPCO_REPO_UPSTREAM_COMMIT="77f2e84e4b6f9d667d8733967301dbdad4e795de"
readonly ROCM_DS_CMAKE_REPO_UPSTREAM_COMMIT="3d18139480d28a77ea0b2e5980f2d2317a114a91"
readonly COMFYUI_VALD_MODEL_REPO_TYPE="model"
readonly COMFYUI_VALD_MODEL_REPO_RELPATH="Comfy-Org/flux1-dev"
readonly COMFYUI_VALD_MODEL_REPO_COMMIT="ca7d619b1bcd7156ca897f55efb2370eba3d9e20"
readonly HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT="0.0"

# This is a jq program passed as one quoted argument, not shell syntax for later
#     evaluation.
# shellcheck disable=SC2089
readonly COMFYUI_WORKFLOW_MODLNAME_FILTER='.nodes[] | select(.type == "CheckpointLoaderSimple").widgets_values[0]'

# These are sourced constants, not process-environment controls. Clear any
#     inherited export attributes before the validator launches child commands.
export -n TRITON_REPO_LOCAL_DIRNAME HIPCO_REPO_LOCAL_DIRNAME
export -n ROCM_DS_CMAKE_REPO_LOCAL_DIRNAME LIB_DIR_RELPATH
export -n TRITON_EXAMPLE_PATCH_RELPATH HIPCO_CMAKE_PATCH_RELPATH
export -n ROCM_DS_CMAKE_HIPCXX_PATCH_RELPATH FLUX_1_DEV_WORKFLOW_RELPATH
export -n TRITON_REPO_UPSTREAM_TAG HIPCO_REPO_UPSTREAM_COMMIT
export -n ROCM_DS_CMAKE_REPO_UPSTREAM_COMMIT COMFYUI_VALD_MODEL_REPO_TYPE
export -n COMFYUI_VALD_MODEL_REPO_RELPATH COMFYUI_VALD_MODEL_REPO_COMMIT
export -n HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT
# shellcheck disable=SC2090 # This changes an attribute; it does not expand the value.
export -n COMFYUI_WORKFLOW_MODLNAME_FILTER
