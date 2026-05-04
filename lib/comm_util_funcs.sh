
# Guarded version of 'rm --recursive --force [FILES...]' that checks that
#     the directories/files/etc. being deleted are not outside of the current
#     user's home directory or is the home directory itself
# Usage: guarded_rm_rf [files]...
guarded_rm_rf() {

    _permitted_root_dir=""
    _curr_username=$(id --user --name) || {
        echo "FAILED to get effective user name string!" >&2
        exit 1
    }
    if [ "${_curr_username}" = "root" ]; then
        _permitted_root_dir="/root"
    else
        _permitted_root_dir="/home/${_curr_username}"
    fi
    if [ ! -d "${_permitted_root_dir}" ]; then
        echo "Expected directory '${_permitted_root_dir}' does NOT exist!"
        exit 1
    fi

    _str_paths_list="$(realpath --canonicalize-missing "$@")"
    _old_ifs="$IFS"
    # Don't let command substitution swallow trailing newlines
    IFS="$(printf '\n%s' ".")"
    IFS="${IFS%.}"
    for str_path in ${_str_paths_list}; do
        if echo "${str_path}" | \
                grep --quiet --invert-match "^${_permitted_root_dir}/"; then
            echo "Refusing to forcefully and recursively delete path" >&2
            echo "    corresponding to '${str_path}'," >&2
            echo "    since it is not a path that starts with" \
                                "'${_permitted_root_dir}/'!" >&2
            exit 1
        elif [ "${str_path}" = "${_permitted_root_dir}/" ]; then
            echo "Refusing to forcefully and recursively delete path" >&2
            echo "    '${_permitted_root_dir}' itself!" >&2
            exit 1
        fi
    done
    IFS="${_old_ifs}"

    # We execute this only after checks have passed and
    #     WITHOUT sudo
    rm --recursive --force "$@"

}

