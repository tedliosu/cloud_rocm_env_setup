
_CURR_USERNAME="$(whoami)"
CURR_HOME_DIR="/home/${_CURR_USERNAME}"
if [ "${_CURR_USERNAME}" = "root" ]; then
    CURR_HOME_DIR="/root"
fi
export CURR_HOME_DIR

