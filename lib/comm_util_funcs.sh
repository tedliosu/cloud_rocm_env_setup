
# Any reference of "BASELINE" below means REPO-SPECIFIC DEFINED BASELINE!
readonly UFW_INSTALLED_FRESH="UFW_FRESH"
readonly UFW_KNOWN_BASELINE="UFW_BASELINE"
readonly UFW_CUSTOM_STATE="UFW_CUSTOM_STAT"
readonly UFW_UNK_STATE="UFW_UNKNOWN_STAT"
# Trailing whitespace in this is INTENTIONAL for fingerprinting!
readonly _UFW_BASELINE_STATUS_CONTENTS="Status: active

To                         Action      From
--                         ------      ----
22/tcp                     ALLOW       Anywhere                  
22/tcp (v6)                ALLOW       Anywhere (v6)             "
readonly _UFW_FRESH_STATUS_CONTENTS="Status: inactive"
readonly _UFW_BASELINE_ADDED_CONTENTS="Added user rules (see 'ufw status' for running firewall):
ufw allow 22/tcp"
readonly _UFW_FRESH_ADDED_CONTENTS="Added user rules (see 'ufw status' for running firewall):
(None)"
readonly _UFW_EXPECTED_DEFAULTS_CONTENTS="IPV6=yes
DEFAULT_INPUT_POLICY=\"DROP\"
DEFAULT_OUTPUT_POLICY=\"ACCEPT\"
DEFAULT_FORWARD_POLICY=\"DROP\"
DEFAULT_APPLICATION_POLICY=\"SKIP\""

# Check that the collected /etc/default/ufw values contain each expected key
#     exactly once.
# Usage: _ufw_defaults_are_interpretable <collected_default_values>
# Returns: 0 if the collected values are interpretable; 1 otherwise
_ufw_defaults_are_interpretable() {

    [ "$(printf "%s\n" "${1}" | wc -l)" -eq 5 ] || return 1

    [ "$(printf "%s\n" "${1}" |
        grep --extended-regexp --count '^IPV6=(yes|no)$')" -eq 1 ] || return 1

    for _ufw_default_key in DEFAULT_INPUT_POLICY DEFAULT_OUTPUT_POLICY \
        DEFAULT_FORWARD_POLICY; do
        [ "$(printf "%s\n" "${1}" |
            grep --extended-regexp --count \
                "^${_ufw_default_key}=\"(ACCEPT|DROP|REJECT)\"$")" -eq 1 ] ||
            return 1
    done

    [ "$(printf "%s\n" "${1}" |
        grep --extended-regexp --count \
            '^DEFAULT_APPLICATION_POLICY="(ACCEPT|DROP|REJECT|SKIP)"$')" -eq 1 ] ||
        return 1

}

# Classify separately collected UFW observations. The classification is printed
#     to stdout; this function does not return it by mutating caller state.
# Usage: classify_ufw_state <ufw_status> <ufw_show_added> <ufw_defaults>
# Returns: 0 after printing the UFW classification
classify_ufw_state() {

    if [ "${1}" = "${_UFW_BASELINE_STATUS_CONTENTS}" ] &&
        [ "${2}" = "${_UFW_BASELINE_ADDED_CONTENTS}" ] &&
        [ "${3}" = "${_UFW_EXPECTED_DEFAULTS_CONTENTS}" ]; then
        printf "%s\n" "${UFW_KNOWN_BASELINE}"
        return 0
    elif [ "${1}" = "${_UFW_FRESH_STATUS_CONTENTS}" ] &&
        [ "${2}" = "${_UFW_FRESH_ADDED_CONTENTS}" ] &&
        [ "${3}" = "${_UFW_EXPECTED_DEFAULTS_CONTENTS}" ]; then
        printf "%s\n" "${UFW_INSTALLED_FRESH}"
        return 0
    fi

    case $(printf "%s\n" "${1}" | sed -n '1p') in
        "Status: active"|"Status: inactive")
            if _ufw_defaults_are_interpretable "${3}"; then
                printf "%s\n" "${UFW_CUSTOM_STATE}"
            else
                printf "%s\n" "${UFW_UNK_STATE}"
            fi
            ;;
        *)
            printf "%s\n" "${UFW_UNK_STATE}"
            ;;
    esac

}

# Print the collected UFW observations without attempting to interpret arbitrary
#     custom rules.
# Usage: print_ufw_diagnostics <ufw_status> <ufw_show_added> <ufw_defaults>
# Returns: 0 after printing the collected UFW diagnostics
print_ufw_diagnostics() {

    printf '%s\n' "--- collected 'ufw status' output is ---" >&2
    printf '%s\n' "${1}" >&2
    printf '%s\n' "--- collected 'ufw show added' output is ---" >&2
    printf '%s\n' "${2}" >&2
    printf '%s\n' "--- collected /etc/default/ufw values are ---" >&2
    printf '%s\n' "${3}" >&2
    printf '%s\n' "--- EXPECTED UFW baseline is ---" >&2
    printf '%s\n' "${_UFW_BASELINE_STATUS_CONTENTS}" >&2
    printf '%s\n' "${_UFW_BASELINE_ADDED_CONTENTS}" >&2
    printf '%s\n' "${_UFW_EXPECTED_DEFAULTS_CONTENTS}" >&2

    dpkg-query --show \
        --showformat='--- INFO: UFW detected dpkg version: ${Version} ---\n' \
        ufw 2>/dev/null || :

}

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
