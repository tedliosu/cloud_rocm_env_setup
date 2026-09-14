
# shellcheck shell=bash
# This file is sourced by setup and validation entry scripts; standalone
#     analysis cannot see its consumers.
# shellcheck disable=SC2034

_CURR_USERNAME="$(whoami)"
CURR_HOME_DIR="/home/${_CURR_USERNAME}"
if [ "${_CURR_USERNAME}" = "root" ]; then
    CURR_HOME_DIR="/root"
fi
if [ -d "${CURR_HOME_DIR}" ]; then
    readonly CURR_HOME_DIR
else
    echo "ERROR: expected directory '$CURR_HOME_DIR' does not exist!" >&2
    exit 1
fi
readonly DEEP_LEARN_VIRTENV_DIR="${CURR_HOME_DIR}/deep_learn_pyenv"
readonly GPU_ARR_VIRTENV_DIR="${CURR_HOME_DIR}/gpgpu_arr_pyenv"
readonly CUPY_REPO_LOCAL_DIR="${CURR_HOME_DIR}/local_cupy_repo_clone"
readonly COMFYUI_REPO_LOCAL_DIR="${CURR_HOME_DIR}/local_comfyui_clone"
_PROJ_ETC_DIR_RELPATH="../../common/etc"
readonly MILESTONES_DIR_RELPATH="../state_trackers"
readonly LOGS_DIR_RELPATH="../logs"
readonly TEMP_DIR_RELPATH="../temp"
readonly CUPY_BUILD_LOG_RELPATH="${LOGS_DIR_RELPATH}/cupy_build.log"
readonly APT_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/common_apt_reqs.txt"
readonly TORCH_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/torch_requirements.txt"
readonly NON_TORCH_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/other_ml_requirements.txt"
readonly GPU_ARR_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/gpu_arr_non_cupy_requirements.txt"
readonly PRE_COMFYUI_PIP_FREEZE_RECS="${LOGS_DIR_RELPATH}/before_comfyui.deep_learn_pyenv.txt"
readonly POST_COMFYUI_PIP_FREEZE_RECS="${LOGS_DIR_RELPATH}/after_comfyui.deep_learn_pyenv.txt"

readonly TORCHCODEC_PIN_VER="0.11.0"
readonly COMFYUI_PIN_VER_TAG="v0.19.0"
readonly CUPY_PIN_VER_TAG="v14.1.1"

readonly ONEAPI_TBB_PIN_VER="2023.0"
readonly ONEAPI_TCM_PIN_VER="1.5"

# Deliberately shared by the supported Ubuntu 24.04 baseline recipes. Move this
#     to provider variables if their OS generations or CMake requirements split.
readonly CMAKE_APT_PIN_VER="4.4.2-0kitware1ubuntu24.04.1"

# Entry scripts consume these as sourced shell values and pass selected values
#     explicitly. Clear any inherited export attributes so they do not leak to
#     unrelated child processes.
export -n CURR_HOME_DIR DEEP_LEARN_VIRTENV_DIR GPU_ARR_VIRTENV_DIR
export -n CUPY_REPO_LOCAL_DIR COMFYUI_REPO_LOCAL_DIR MILESTONES_DIR_RELPATH
export -n LOGS_DIR_RELPATH TEMP_DIR_RELPATH CUPY_BUILD_LOG_RELPATH
export -n APT_ONLY_REQS_TXT_RELPATH TORCH_ONLY_REQS_TXT_RELPATH
export -n NON_TORCH_REQS_TXT_RELPATH GPU_ARR_REQS_TXT_RELPATH
export -n PRE_COMFYUI_PIP_FREEZE_RECS POST_COMFYUI_PIP_FREEZE_RECS
export -n TORCHCODEC_PIN_VER COMFYUI_PIN_VER_TAG CUPY_PIN_VER_TAG
export -n ONEAPI_TBB_PIN_VER ONEAPI_TCM_PIN_VER CMAKE_APT_PIN_VER
