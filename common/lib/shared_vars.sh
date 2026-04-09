
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
_PROJ_ETC_DIR_RELPATH="../../common/etc"
export APT_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/common_apt_reqs.txt"
export TORCH_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/torch_requirements.txt"
export NON_TORCH_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/other_ml_requirements.txt"
export GPU_ARR_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/gpu_arr_non_cupy_requirements.txt"

