
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
_PROJ_ETC_DIR_RELPATH="../../common/etc"
export APT_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/common_apt_reqs.txt"
export TORCH_ONLY_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/torch_requirements.txt"
export NON_TORCH_REQS_TXT_RELPATH="${_PROJ_ETC_DIR_RELPATH}/other_ml_requirements.txt"

