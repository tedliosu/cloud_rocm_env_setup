#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
readonly REPO_ROOT
readonly -a SETUP_SOURCE_VARIABLES=(
    CURR_HOME_DIR
    DEEP_LEARN_VIRTENV_DIR
    GPU_ARR_VIRTENV_DIR
    PACKAGED_AMD_RAPIDS_VIRTENV_DIR
    CUPY_REPO_LOCAL_DIR
    COMFYUI_REPO_LOCAL_DIR
    MILESTONES_DIR_RELPATH
    LOGS_DIR_RELPATH
    TEMP_DIR_RELPATH
    CUPY_BUILD_LOG_RELPATH
    APT_ONLY_REQS_TXT_RELPATH
    TORCH_ONLY_REQS_TXT_RELPATH
    NON_TORCH_REQS_TXT_RELPATH
    GPU_ARR_REQS_TXT_RELPATH
    PRE_COMFYUI_PIP_FREEZE_RECS
    POST_COMFYUI_PIP_FREEZE_RECS
    TORCHCODEC_PIN_VER
    COMFYUI_PIN_VER_TAG
    CUPY_PIN_VER_TAG
    ONEAPI_TBB_PIN_VER
    ONEAPI_TCM_PIN_VER
    CMAKE_APT_PIN_VER
)
readonly -a VALIDATION_SOURCE_VARIABLES=(
    TRITON_REPO_LOCAL_DIRNAME
    HIPCO_REPO_LOCAL_DIRNAME
    ROCM_DS_CMAKE_REPO_LOCAL_DIRNAME
    LIB_DIR_RELPATH
    TRITON_EXAMPLE_PATCH_RELPATH
    HIPCO_CMAKE_PATCH_RELPATH
    ROCM_DS_CMAKE_HIPCXX_PATCH_RELPATH
    FLUX_1_DEV_WORKFLOW_RELPATH
    TRITON_REPO_UPSTREAM_TAG
    HIPCO_REPO_UPSTREAM_COMMIT
    ROCM_DS_CMAKE_REPO_UPSTREAM_COMMIT
    COMFYUI_VALD_MODEL_REPO_TYPE
    COMFYUI_VALD_MODEL_REPO_RELPATH
    COMFYUI_VALD_MODEL_REPO_COMMIT
    HIPCIM_CANNY_MAX_DISAGREEMENT_PERCENT
    COMFYUI_WORKFLOW_MODLNAME_FILTER
)
readonly -a AZURE_SOURCE_VARIABLES=(
    EXPECTED_DISTRO
    EXPECTED_DIST_VER
    EXPECTED_DIST_CODENAME
    EXPECTED_ROCM_VER
    EXPECTED_ROCMVER_REGEX
    FASTFETCH_PIN_VER
    FASTFETCH_DEB_FILENAME
)
readonly -a HOT_AISLE_SOURCE_VARIABLES=(
    EXPECTED_DISTRO
    EXPECTED_DIST_VER
    EXPECTED_DIST_CODENAME
    EXPECTED_ROCM_VER
    EXPECTED_ROCMVER_REGEX
    FASTFETCH_PPA_FULLPATH
    FASTFETCH_PPA_URL
)

assert_not_exported() {
    local _variable_name

    for _variable_name in "$@"; do
        if env | grep --extended-regexp --quiet \
            "^${_variable_name}="; then
            echo "FAILED: sourced variable '${_variable_name}' remained exported!" >&2
            exit 1
        fi
    done
}

(
    export CURR_HOME_DIR="/ambient/home"
    export DEEP_LEARN_VIRTENV_DIR="/ambient/deep-learning"
    export CMAKE_APT_PIN_VER="ambient-version"

    cd "${REPO_ROOT}/setup/amd_devcloud/bin"
    # shellcheck source=../lib/shared_vars.sh
    . "../../common/lib/shared_vars.sh"

    [ "${DEEP_LEARN_VIRTENV_DIR}" = "${CURR_HOME_DIR}/deep_learn_pyenv" ]
    [ "${CMAKE_APT_PIN_VER}" = "4.4.2-0kitware1ubuntu24.04.1" ]
    assert_not_exported "${SETUP_SOURCE_VARIABLES[@]}"
)

(
    export TRITON_REPO_LOCAL_DIRNAME="ambient-triton"
    export COMFYUI_VALD_MODEL_REPO_TYPE="ambient-model-type"

    cd "${REPO_ROOT}/validate/bin"
    # shellcheck source=../../../validate/lib/vald_shared_vars.sh
    . "../lib/vald_shared_vars.sh"

    [ "${TRITON_REPO_LOCAL_DIRNAME}" = "local_triton_repo" ]
    [ "${COMFYUI_VALD_MODEL_REPO_TYPE}" = "model" ]
    assert_not_exported "${VALIDATION_SOURCE_VARIABLES[@]}"
)

(
    # Each provider owns constants with the same names. Subshells deliberately
    #     isolate their readonly declarations and ambient-value fixtures.
    # shellcheck disable=SC2030
    export EXPECTED_DISTRO="Ambient Linux"
    export FASTFETCH_PIN_VER="ambient-version"

    cd "${REPO_ROOT}/setup/azure/bin"
    # shellcheck source=../../azure/lib/azure_vars.sh
    . "../lib/azure_vars.sh"

    [ "${EXPECTED_DISTRO}" = "Ubuntu" ]
    [ "${FASTFETCH_PIN_VER}" = "2.62.1" ]
    assert_not_exported "${AZURE_SOURCE_VARIABLES[@]}"
)

(
    # See the intentional provider-test isolation above.
    # shellcheck disable=SC2031
    export EXPECTED_DISTRO="Ambient Linux"
    export FASTFETCH_PPA_URL="ambient-url"

    cd "${REPO_ROOT}/setup/hot_aisle/bin"
    # shellcheck source=../../hot_aisle/lib/hot_aisle_vars.sh
    . "../lib/hot_aisle_vars.sh"

    [ "${EXPECTED_DISTRO}" = "Ubuntu" ]
    [[ "${FASTFETCH_PPA_URL}" == *"/noble/Release" ]]
    assert_not_exported "${HOT_AISLE_SOURCE_VARIABLES[@]}"
)

echo "PASSED source-only variable scope tests!"
