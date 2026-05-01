
_CURR_USERNAME="$(whoami)"
CURR_HOME_DIR="/home/${_CURR_USERNAME}"
if [ "${_CURR_USERNAME}" = "root" ]; then
    CURR_HOME_DIR="/root"
fi
if [ -d "${CURR_HOME_DIR}" ]; then
    export CURR_HOME_DIR
else
    echo "ERROR: expected directory '$CURR_HOME_DIR' does not exist!" >&2
    exit 1
fi
export DEEP_LEARN_VIRTENV_DIR="${CURR_HOME_DIR}/deep_learn_pyenv"
export GPU_ARR_VIRTENV_DIR="${CURR_HOME_DIR}/gpgpu_arr_pyenv"
export CUPY_REPO_LOCAL_DIR="${CURR_HOME_DIR}/local_cupy_repo_clone"
export COMFYUI_REPO_LOCAL_DIR="${CURR_HOME_DIR}/local_comfyui_clone"
_PROJ_ETC_DIR_RELPATH="../../common/etc"
export MILESTONES_DIR_RELPATH="../state_trackers"
export LOGS_DIR_RELPATH="../logs"
export APT_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/common_apt_reqs.txt"
export TORCH_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/torch_requirements.txt"
export NON_TORCH_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/other_ml_requirements.txt"
export GPU_ARR_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/gpu_arr_non_cupy_requirements.txt"
export PRE_COMFYUI_PIP_FREEZE_RECS="${LOGS_DIR_RELPATH}/before_comfyui.deep_learn_pyenv.txt"
export POST_COMFYUI_PIP_FREEZE_RECS="${LOGS_DIR_RELPATH}/after_comfyui.deep_learn_pyenv.txt"

export TORCHCODEC_PIN_VER="0.11.0"
export COMFYUI_PIN_VER_TAG="v0.19.0"

export ONEAPI_TBB_PIN_VER="2023.0"
export ONEAPI_TCM_PIN_VER="1.5"

