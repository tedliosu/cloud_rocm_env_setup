# shellcheck shell=bash

# Source global helpers used in this script;
#    note that this sourcing assumes that the
#    main runner script will reside in directory
#    '../../*/bin' relative to this script!
. "../../../lib/comm_util_funcs.sh"

readonly _NEWLINE='
'
readonly _CUPY_BUILD_LOG_TAIL_LINES=80

# Helper function to run a stage
# Usage: run_stage <milestones_directory_path> <function_to_run> [function_arguments]...
# Invoke directly, for example: run_stage "${MILESTONES_DIR}" stage_function [arguments]...
# Do not invoke from 'if', with '!', or as part of an '&&'/'||' list because
#     those conditional contexts disable 'errexit' throughout the stage function.
run_stage() {

    local _stage_status
    local _milestones_dir
    local _func_to_run
    local _done_marker_file
    local _skip_stage_msg
    _milestones_dir="$1"
    shift
    _func_to_run="$1"
    shift
    _done_marker_file="${_milestones_dir}/${_func_to_run}.done"
    _skip_stage_msg="--- skipping stage: ${_func_to_run} (already complete) ---"

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        if [ ! -f "${_done_marker_file}" ]; then
            echo "[PLAN ONLY] --- would run stage ${_func_to_run} ---"
        else
            echo "[PLAN ONLY] ${_skip_stage_msg}"
        fi
        return 0
    fi

    if [ ! -f "${_done_marker_file}" ]; then
        echo "--- starting stage: ${_func_to_run} ---"

        # A function invoked in a conditional context ignores 'errexit' throughout
        #     its body, so run the stage as a plain command in an isolated shell.
        set +e
        (
            set -e
            "${_func_to_run}" "$@"
        )
        _stage_status="$?"
        set -e

        if [ "${_stage_status}" -ne 0 ] || ! touch "${_done_marker_file}"; then
            echo "--- FAILED stage: ${_func_to_run} ---" >&2
            exit 1
        fi
        echo "--- completed stage: ${_func_to_run} ---"
    else
        echo "${_skip_stage_msg}"
    fi

}

# Confirm that SSH_CONNECTION contains exactly four non-empty fields on one line
#     and that its server-side port is the project baseline port, TCP/22.
# Usage: _current_ssh_connection_uses_port_22 <ssh_connection_value>
# Returns: 0 if SSH_CONNECTION is valid and uses server port 22; 1 otherwise
_current_ssh_connection_uses_port_22() {

    case ${1} in
        *"${_NEWLINE}"*)
            echo "ERROR: SSH_CONNECTION must not contain multiple lines!" >&2
            return 1
            ;;
    esac

    if ! printf "%s\n" "${1}" |
        grep --extended-regexp --line-regexp --quiet \
            '[^[:blank:]]+([[:blank:]]+[^[:blank:]]+){3}'; then
        echo "ERROR: SSH_CONNECTION should contain exactly 4" >&2
        echo "    non-empty fields all on the same line!" >&2
        return 1
    fi

    set -- "${1}" "$(printf "%s\n" "${1}" | awk '{ print $4 }')"
    if [ "${2}" != "22" ]; then
        echo "--- WARNING: expected current SSH server port is 22 ---" >&2
        echo "---     got port ${2} instead ---" >&2
        echo "--- NOT modifying current UFW state! ---" >&2
        return 1
    fi

}

# Check whether the UFW baseline is already satisfied or can be safely applied,
#     and apply it only from the exact known FRESH state.
# This top-level function owns the script's collected-observation working values.
# Usage: no arguments required
# Returns: 0 for plan-only, BASELINE, CUSTOM, or successfully initialized FRESH;
#          1 for UNKNOWN or any unsafe/failed initialization condition
check_n_apply_ufw_base_or_warn_dont_wrap() (

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would refresh APT metadata and install UFW if missing."
        echo "[PLAN ONLY] Would inspect current UFW state and apply the project"
        echo "[PLAN ONLY]     firewall baseline only from a known fresh state."
        return 0
    fi

    # Keep command output used for exact UFW comparisons stable without changing
    #     the locale of unrelated setup stages.
    LC_ALL=C
    export LC_ALL

    if ! command -v ufw >/dev/null 2>&1; then
        echo "UFW installation NOT detected; refreshing APT metadata before installation..."
        if ! sudo --set-home apt-get update; then
            echo "ERROR: unable to refresh APT metadata before installing 'ufw'!" >&2
            return 1
        elif ! sudo --set-home apt-get install --assume-yes ufw; then
            echo "ERROR: unable to install 'ufw'!" >&2
            return 1
        fi
    fi

    if ! _collected_ufw_status=$(sudo --set-home ufw status 2>/dev/null) ||
        ! _collected_ufw_added=$(sudo --set-home ufw show added 2>/dev/null) ||
        ! _collected_ufw_defaults=$(sudo --set-home \
            grep --extended-regexp \
                "${UFW_DEFAULTS_SELECTOR_REGEX}" \
                /etc/default/ufw 2>/dev/null); then
        echo "ERROR: unable to collect current UFW state!" >&2
        echo "   Please check output of each of following commands manually:" >&2
        echo "     1. sudo -H ufw status" >&2
        echo "     2. sudo -H ufw show added" >&2
        printf "     3. sudo -H grep -E '%s' /etc/default/ufw\n" \
            "${UFW_DEFAULTS_SELECTOR_REGEX}" >&2
        return 1
    fi
    _ufw_classification=$(classify_ufw_state "${_collected_ufw_status}" \
        "${_collected_ufw_added}" "${_collected_ufw_defaults}")

    dpkg-query --show \
        --showformat='INFO: detected Ubuntu UFW package version: ${Version}.\n' \
        ufw 2>/dev/null || :

    case ${_ufw_classification} in
        "${UFW_KNOWN_BASELINE}")
            echo "UFW baseline state already in effect; not modifying current UFW state..."
            return 0
            ;;
        "${UFW_INSTALLED_FRESH}")
            echo "UFW is in a known fresh state; proceeding to apply a sane UFW baseline state..."
            ;;
        "${UFW_CUSTOM_STATE}")
            printf '%s\n' "--- WARNING: UFW classification is ${_ufw_classification} ---" >&2
            print_ufw_diagnostics "${_collected_ufw_status}" \
                "${_collected_ufw_added}" \
                "${_collected_ufw_defaults}"
            printf '%s\n' "--- NOT modifying current UFW state! ---" >&2
            return 0
            ;;
        "${UFW_UNK_STATE}")
            printf '%s\n' "--- WARNING: UFW classification is ${_ufw_classification} ---" >&2
            print_ufw_diagnostics "${_collected_ufw_status}" \
                "${_collected_ufw_added}" \
                "${_collected_ufw_defaults}"
            printf '%s\n' "--- NOT modifying current UFW state! ---" >&2
            return 1
            ;;
        *)
            echo "ERROR: internal UFW classification failure!" >&2
            return 1
            ;;
    esac

    if ! _current_ssh_connection_uses_port_22 "${SSH_CONNECTION-}"; then
        return 1
    fi

    echo "Configuring UFW baseline from known good fresh state..."
    if ! sudo --set-home ufw allow 22/tcp; then
        echo "ERROR: unable to add the UFW TCP/22 allow rule!" >&2
        return 1
    elif ! sudo --set-home ufw default allow outgoing; then
        echo "ERROR: unable to set the UFW default outgoing policy!" >&2
        echo "WARNING: UFW may now be in a partial custom state; no rollback was attempted." >&2
        return 1
    elif ! sudo --set-home ufw default deny incoming; then
        echo "ERROR: unable to set the UFW default incoming policy!" >&2
        echo "WARNING: UFW may now be in a partial custom state; no rollback was attempted." >&2
        return 1
    elif ! sudo --set-home ufw --force enable; then
        echo "ERROR: unable to enable UFW!" >&2
        echo "WARNING: UFW may now be in a partial custom state; no rollback was attempted." >&2
        return 1
    fi
    echo "UFW baseline configuration commands completed."

    if ! _collected_ufw_status=$(sudo --set-home ufw status 2>/dev/null) ||
        ! _collected_ufw_added=$(sudo --set-home ufw show added 2>/dev/null) ||
        ! _collected_ufw_defaults=$(sudo --set-home \
            grep --extended-regexp \
                "${UFW_DEFAULTS_SELECTOR_REGEX}" \
                /etc/default/ufw 2>/dev/null); then
        echo "ERROR: unable to collect UFW state after baseline configuration!" >&2
        return 1
    fi
    _ufw_classification=$(classify_ufw_state "${_collected_ufw_status}" \
        "${_collected_ufw_added}" "${_collected_ufw_defaults}")

    if [ "${_ufw_classification}" = "${UFW_KNOWN_BASELINE}" ]; then
        echo "UFW baseline configuration sanity check passed!"
        return 0
    fi

    echo "ERROR: UFW baseline configuration sanity check failed!" >&2
    printf '%s\n' "--- WARNING: UFW classification is ${_ufw_classification} ---" >&2
    print_ufw_diagnostics "${_collected_ufw_status}" \
        "${_collected_ufw_added}" \
        "${_collected_ufw_defaults}"
    return 1

)

# Return whether a whitespace-separated group list contains one exact group.
# Usage: _group_list_contains <group_list> <group_name>
# Returns: 0 if the group is present; 1 otherwise
_group_list_contains() {

    [ "$#" -eq 2 ] || return 1
    case " ${1} " in
        *" ${2} "*) return 0;;
        *) return 1;;
    esac

}

# Ensure that the login user is configured for and currently has GPU groups.
# Usage: no arguments required
ensure_groups_maybe_require_relogin_dont_wrap() {

    local _env_username
    local _effective_username
    local _configured_groups
    local _effective_groups
    local _group_name
    local _missing_group_csv
    local -a _missing_groups=()
    local -a _required_groups=(video render)

    _env_username="$(logname)" || {
        echo "FAILED to get 'LOGNAME'!" >&2
        exit 1
    }

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would ensure that user '${_env_username}' is" \
             "in 'video' and 'render' groups."
        echo "[PLAN ONLY]     A new SSH login would be required if memberships changed."
        return 0
    fi

    if ! _effective_username="$(id --user --name)"; then
        echo "ERROR: failed to determine the effective user!" >&2
        exit 1
    fi
    if [ "${_effective_username}" != "${_env_username}" ]; then
        echo "ERROR: effective user '${_effective_username}' does not match" >&2
        echo "    login user '${_env_username}'! Run setup as the login user." >&2
        exit 1
    fi
    if ! _configured_groups="$(id --name --groups "${_env_username}")"; then
        echo "ERROR: failed to inspect configured groups for '${_env_username}'!" >&2
        exit 1
    fi
    if ! _effective_groups="$(id --name --groups)"; then
        echo "ERROR: failed to inspect effective groups for this login session!" >&2
        exit 1
    fi

    echo "Ensuring that user '${_env_username}' is" \
         "in 'video' and 'render' groups..."

    for _group_name in "${_required_groups[@]}"; do
        if ! _group_list_contains "${_configured_groups}" "${_group_name}"; then
            _missing_groups+=("${_group_name}")
        fi
    done
    if [ "${#_missing_groups[@]}" -gt 0 ]; then
        _missing_group_csv="$(IFS=,; printf "%s" "${_missing_groups[*]}")"
        echo "Adding '${_env_username}' to missing groups: ${_missing_group_csv}"
        if ! sudo --set-home usermod --append --groups \
            "${_missing_group_csv}" "${_env_username}"; then
            echo "ERROR: failed to update GPU group memberships!" >&2
            exit 1
        fi
        if ! _configured_groups="$(id --name --groups "${_env_username}")"; then
            echo "ERROR: failed to recheck configured GPU groups!" >&2
            exit 1
        fi
        for _group_name in "${_required_groups[@]}"; do
            if ! _group_list_contains "${_configured_groups}" "${_group_name}"; then
                echo "ERROR: '${_group_name}' membership was not configured!" >&2
                exit 1
            fi
        done
        echo "GPU group memberships changed."
        echo "Log out of this SSH session completely, reconnect, and rerun setup."
        exit 0
    fi

    for _group_name in "${_required_groups[@]}"; do
        if ! _group_list_contains "${_effective_groups}" "${_group_name}"; then
            echo "ERROR: '${_group_name}' is configured but is not effective" >&2
            echo "    in this login session. Log out completely, reconnect," >&2
            echo "    and rerun setup." >&2
            exit 1
        fi
    done
    echo "Required video and render groups are effective in this login session."

}

# Assert basic OS environment stats helper, assuming an expected distro ID
# Usage: ensure_basic_os_env_sanity_dont_wrap <expected_distro_name> <expected_distro_ver>
# Returns: 0 for plan-only or the expected OS; exits 1 for an unexpected OS
ensure_basic_os_env_sanity_dont_wrap() {
    local _expected_distro_id="${1,,}"

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would ensure that current environment is $1 $2 distro."
        return 0
    fi

    if ! os_release_matches_expected /etc/os-release \
        "${_expected_distro_id}" "$2"; then
        echo "Got unexpected '/etc/os-release' with contents:" >&2
        echo >&2
        if [ -r /etc/os-release ]; then
            cat /etc/os-release >&2
        else
            echo "Unable to read '/etc/os-release'." >&2
        fi
        echo >&2
        echo "    This IS NOT $1 $2; bailing!" >&2
        exit 1
    fi

}

# Assert ROCm driver and userland environment stats helper
# Usage: ensure_rocm_env_sanity_dont_wrap <expected_rocm_ver> <expected_rocm_ver_regex>
# Returns: 0 for plan-only or the expected ROCm environment; exits 1 otherwise
ensure_rocm_env_sanity_dont_wrap() {

    local _rocminfo_output
    local _rocminfo_status

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would ensure that amdgpu dkms is loaded according to 'rocminfo',"
        echo "[PLAN ONLY]     and ensure that 'hipconfig' reports ROCm version ~$1."
        return 0
    fi

    if _rocminfo_output="$(rocminfo)"; then
        :
    else
        _rocminfo_status="$?"
        echo "FAILED: 'rocminfo' exited with status ${_rocminfo_status}!" >&2
        echo "    Unable to inspect the AMDGPU driver." >&2
        exit 1
    fi
    if grep --ignore-case --quiet "NOT loaded" <<<"${_rocminfo_output}"; then
        echo "amdgpu dkms not detected; bailing!" >&2
        exit 1
    fi
    ROCM_DETECTED_VER="$(hipconfig --rocmpath | cut --delimiter="-" --fields=2)"
    if echo "$ROCM_DETECTED_VER" | \
       grep --extended-regexp --invert-match --quiet "$2"; then
        echo "'hipconfig' reports ROCm userland version $ROCM_DETECTED_VER!" >&2
        echo >&2
        echo "    Please update all environment setup logic and configs" >&2
        echo >&2
        echo "    before rerunning this script, as assumed version is" >&2
        echo " ~$1!" >&2
        exit 1
    fi

}

# Check web hosted file availability using wget with http(s)
# Usage: check_wget_fetch_dont_wrap <web_url_to_file>
# Returns: 0 on success of web hosted file fetch; 1 otherwise
check_wget_fetch_dont_wrap() {

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would check whether '$1' is reachable,"
        echo "[PLAN ONLY]     using 'wget'; real run would install 'wget' first"
        echo "[PLAN ONLY]     if unavailable."
        return 0
    fi

    _prereq_pkgs_wget_check="ca-certificates wget"
    # safe because apt package names each NEVER contain whitespace(s)
    # shellcheck disable=SC2086
    dpkg --status ${_prereq_pkgs_wget_check} >/dev/null 2>&1 || \
        sudo --set-home apt-get install --assume-yes ${_prereq_pkgs_wget_check}
    if wget --quiet --tries=3 --timeout=10 --output-document=/dev/null "$1"; then
        echo "PASS: $1 is reachable!"
        return 0
    else
        echo "WARNING: $1 is NOT reachable!" >&2
        return 1
    fi

}

# Disable a problematic PPA
# Usage: ppa_disable_dont_wrap <full_path_to_apt_list_file>
ppa_disable_dont_wrap() {

    _file_backup_suffix="bak"

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        if [ -f "${1}.${_file_backup_suffix}" ]; then
            echo "[PLAN ONLY] Would report that PPA(s) in '$1'"
            echo "[PLAN ONLY]     are already disabled."
        else
            echo "[PLAN ONLY] Would attempt to disable PPA(s) in '$1'"
            echo "[PLAN ONLY]     via 'mv' command."
        fi
        return 0
    fi

    if [ -f "$1" ]; then
        sudo --set-home mv "$1" "${1}.${_file_backup_suffix}"
        echo "PPA(s) in '$1' successfully disabled!"
    elif [ -f "${1}.${_file_backup_suffix}" ]; then
        echo "PPA(s) in '$1' already disabled!"
    else
        echo "ERROR; '$1' is NOT a valid path to a file" >&2
        echo "containing one or more PPAs!" >&2
        exit 1
    fi

}

# Upgrade currently installed system packages without promising that
#     kernel-related packages remain unchanged.
# Usage: no arguments required
apt_get_sys_update() {
    sudo --set-home apt-get update
    sudo --set-home env DEBIAN_FRONTEND="noninteractive" \
        NEEDRESTART_MODE="a" apt-get upgrade --assume-yes
}

# Install tmux for persistent remote setup sessions after the one-time reboot
# Usage: no arguments required
# Returns: status of the tmux apt-get installation
ensure_tmux() {
    sudo --set-home apt-get install --assume-yes tmux
}

# Return whether a value has the Linux boot-ID UUID shape.
# Usage: _is_valid_linux_boot_id <boot_id>
# Returns: 0 for one valid boot ID; 1 otherwise
_is_valid_linux_boot_id() {

    [ "$#" -eq 1 ] || return 1
    case ${1} in
        *"${_NEWLINE}"*) return 1;;
    esac
    (
        LC_ALL=C
        export LC_ALL
        printf "%s\n" "${1}" |
            grep --extended-regexp --line-regexp --quiet \
                '[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}'
    )

}

# Read and validate the current Linux boot ID.
# Usage: _read_linux_boot_id
# Returns: 0 after printing one valid boot ID; 1 otherwise
_read_linux_boot_id() {

    local _boot_id

    if ! _boot_id="$(cat /proc/sys/kernel/random/boot_id)"; then
        echo "ERROR: failed to read the current Linux boot ID!" >&2
        return 1
    fi
    if ! _is_valid_linux_boot_id "${_boot_id}"; then
        echo "ERROR: current Linux boot ID is malformed!" >&2
        return 1
    fi
    printf "%s\n" "${_boot_id}"

}

# Request and later acknowledge one reboot for a named setup phase.
# Usage: reboot_with_ack_dont_wrap <milestones_directory> <reboot_phase_name>
reboot_with_ack_dont_wrap() {

    local _milestones_dir
    local _reboot_phase_name
    local _pending_marker_file
    local _done_marker_file
    local _pending_boot_id
    local _current_boot_id
    local _reboot_skip_msg

    if [ "$#" -ne 2 ]; then
        echo "ERROR: reboot_with_ack_dont_wrap expects a milestones" >&2
        echo "    directory and reboot phase name!" >&2
        exit 1
    fi
    _milestones_dir="$1"
    _reboot_phase_name="$2"
    case ${_reboot_phase_name} in
        ''|*[!A-Za-z0-9_]*)
            echo "ERROR: invalid reboot phase name '${_reboot_phase_name}'!" >&2
            exit 1
            ;;
    esac
    _pending_marker_file="${_milestones_dir}/${_reboot_phase_name}.pending"
    _done_marker_file="${_milestones_dir}/${_reboot_phase_name}.done"
    _reboot_skip_msg="--- skipping reboot phase: ${_reboot_phase_name} (already complete) ---"

    if [ -e "${_pending_marker_file}" ] && [ -e "${_done_marker_file}" ]; then
        echo "ERROR: reboot phase '${_reboot_phase_name}' has both pending" >&2
        echo "    and completed state! Refusing to continue." >&2
        exit 1
    fi

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        if [ -f "${_done_marker_file}" ]; then
            echo "[PLAN ONLY] ${_reboot_skip_msg}"
        elif [ -e "${_pending_marker_file}" ]; then
            echo "[PLAN ONLY] Would verify pending reboot phase ${_reboot_phase_name}"
        else
            echo "[PLAN ONLY] Would record reboot phase ${_reboot_phase_name} and reboot system"
        fi
        return 0
    fi

    if [ ! -d "${_milestones_dir}" ]; then
        echo "ERROR: milestones directory '${_milestones_dir}' does not exist!" >&2
        exit 1
    fi

    if [ -f "${_done_marker_file}" ]; then
        echo "${_reboot_skip_msg}"
        return 0
    fi

    if [ -e "${_pending_marker_file}" ]; then
        if [ ! -f "${_pending_marker_file}" ] ||
            ! _pending_boot_id="$(cat "${_pending_marker_file}")" ||
            ! _is_valid_linux_boot_id "${_pending_boot_id}"; then
            echo "ERROR: pending state for reboot phase" >&2
            echo "    '${_reboot_phase_name}' is malformed! Refusing to continue." >&2
            exit 1
        fi
        if ! _current_boot_id="$(_read_linux_boot_id)"; then
            exit 1
        fi
        if [ "${_current_boot_id}" = "${_pending_boot_id}" ]; then
            echo "ERROR: reboot phase '${_reboot_phase_name}' is still pending!" >&2
            echo "    Reboot the system before rerunning setup." >&2
            exit 1
        fi
        if ! mv --no-clobber -- "${_pending_marker_file}" "${_done_marker_file}" ||
            [ -e "${_pending_marker_file}" ] || [ ! -f "${_done_marker_file}" ]; then
            echo "ERROR: failed to acknowledge reboot phase" >&2
            echo "    '${_reboot_phase_name}'!" >&2
            exit 1
        fi
        echo "--- completed reboot phase: ${_reboot_phase_name} ---"
        return 0
    fi

    if ! _current_boot_id="$(_read_linux_boot_id)"; then
        exit 1
    fi
    if ! printf "%s\n" "${_current_boot_id}" > "${_pending_marker_file}"; then
        echo "ERROR: failed to record pending reboot phase" >&2
        echo "    '${_reboot_phase_name}'!" >&2
        exit 1
    fi
    echo "Reboot phase '${_reboot_phase_name}' is required; rebooting..."
    if ! sudo --set-home reboot; then
        echo "ERROR: reboot command failed for phase '${_reboot_phase_name}'!" >&2
        echo "    The pending state was preserved; reboot manually before rerunning." >&2
        exit 1
    fi
    exit 0

}

# Compatibility wrapper retaining the established single-reboot marker name.
# Usage: reboot_once_dont_wrap <milestones_directory>
reboot_once_dont_wrap() {
    reboot_with_ack_dont_wrap "$1" reboot_once_dont_wrap
}

# up-to-date CMake setup, assuming Ubuntu
# Usage: ensure_pinned_cmake <ubuntu_distro_codename> <cmake_pinned_version>
ensure_pinned_cmake() {

    _kitware_test_file="/usr/share/doc/kitware-archive-keyring/copyright"
    _kitware_signing_file="/usr/share/keyrings/kitware-archive-keyring.gpg"
    _signed_by_str="[signed-by=${_kitware_signing_file}]"
    _prereq_pkgs="ca-certificates gpg wget"
    # safe because apt package names each NEVER contain whitespace(s)
    # shellcheck disable=SC2086
    dpkg --status ${_prereq_pkgs} >/dev/null 2>&1 || \
        sudo --set-home apt-get install --assume-yes ${_prereq_pkgs}
    test -f "${_kitware_test_file}" ||
        wget --quiet --output-document=- \
            https://apt.kitware.com/keys/kitware-archive-latest.asc |
                gpg --dearmor - | sudo --set-home tee "${_kitware_signing_file}" >/dev/null
    echo "deb ${_signed_by_str} https://apt.kitware.com/ubuntu/ $1 main" |
        sudo --set-home tee /etc/apt/sources.list.d/kitware.list >/dev/null
    sudo --set-home apt-get update
    test -f "${_kitware_test_file}" || sudo --set-home rm "${_kitware_signing_file}"
    sudo --set-home apt-get install --assume-yes --reinstall kitware-archive-keyring
    sudo --set-home apt-get install --assume-yes "cmake=$2"

}

# Newest Intel oneAPI TBB libraries setup, assuming Ubuntu
# Usage: ensure_oneapi_tbb_libs <oneapi_tbb_version>
ensure_oneapi_tbb_libs() {

    _oneapi_signing_file="/usr/share/keyrings/oneapi-archive-keyring.gpg"
    _signed_by_str_oneapi="[signed-by=${_oneapi_signing_file}]"
    _prereq_pkgs="ca-certificates gpg wget"
    # safe because apt package names each NEVER contain whitespace(s)
    # shellcheck disable=SC2086
    dpkg --status ${_prereq_pkgs} >/dev/null 2>&1 || \
        sudo --set-home apt-get install --assume-yes ${_prereq_pkgs}
    wget --quiet --output-document=- \
        https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | \
            gpg --dearmor - | sudo --set-home tee "${_oneapi_signing_file}" >/dev/null
    echo "deb ${_signed_by_str_oneapi} https://apt.repos.intel.com/oneapi all main" | \
                       sudo --set-home tee /etc/apt/sources.list.d/oneAPI.list >/dev/null
    sudo --set-home apt-get update
    sudo --set-home apt-get install --assume-yes "intel-oneapi-tbb-$1"

}

# Download, install, and configure apt packages with custom settings, assuming Ubuntu
# Usage: ensure_apt_with_custom_conf <current_home_dirpath> <path_to_common_apt_packages_list>
ensure_apt_with_custom_conf() {

    _common_apt_packages="$(<"$2" tr "\n" " " | sed 's/ *$//g')" || {
        echo "FAILED to retrieve apt packages list!" >&2
        exit 1
    }
    _w3m_hidden_dirname=".w3m"
    _w3m_hist_filename="history"
    mkdir --parent "$1/${_w3m_hidden_dirname}"
    sudo --set-home mkdir --parent "/root/${_w3m_hidden_dirname}"
    touch "$1/${_w3m_hidden_dirname}/${_w3m_hist_filename}"
    sudo --set-home touch "/root/${_w3m_hidden_dirname}/${_w3m_hist_filename}"
    # safe because apt package names each NEVER contain whitespace(s)
    # shellcheck disable=SC2086
    sudo --set-home apt-get install --assume-yes ${_common_apt_packages} w3m apt-file
    sudo --set-home apt-file update
    sudo --set-home update-alternatives --set "pager" "/usr/bin/w3m"

}


### ALL FUNCTIONS BELOW ASSUME THAT ALL NEEDED PYTHON SYSTEM PACKAGES SUCH AS
###     python3-pip, python3-virtualenv, etc, AS WELL AS UTLITIES LIKE git, wget,
###     jq, ca-certificates, moreutils, etc, ARE ALREADY PRESENT ON SYSTEM


# Download, install, and configure fastfetch from GitHub releases
# Usage: ensure_github_fastfetch <fastfetch_release_tag> <fastfetch_release_debname> \
#                                <current_home_dirpath> <tmp_files_dirpath>
ensure_github_fastfetch() {

    _api_json_filepath="$4/github_fastfetch_api.json"
    _deb_download_path="$4/$2"
    _fastfetch_config_dir="$3/.config/fastfetch"
    _jq_download_query=".assets[] | select(.name == \"$2\").browser_download_url"
    mkdir --parent "$4"
    wget --quiet --output-document="${_api_json_filepath}" \
        "https://api.github.com/repos/fastfetch-cli/fastfetch/releases/tags/$1" || {
        echo "FAILED: 'wget' GitHub API JSON for 'fastfetch' tag ${1}!" >&2
        exit 1
    }
    _deb_download_url="$(jq --raw-output \
                             "${_jq_download_query}" "${_api_json_filepath}")" || {
        echo "FAILED: querying download link from API JSON!" >&2
        exit 1
    }
    wget --quiet --output-document="${_deb_download_path}" "${_deb_download_url}"
    sudo --set-home dpkg --install "${_deb_download_path}"
    mkdir --parent "${_fastfetch_config_dir}"
    fastfetch --gen-config-full
    jq ".logo.source = \"ubuntu_old\"" "${_fastfetch_config_dir}/config.jsonc" | \
                                        sponge "${_fastfetch_config_dir}/config.jsonc"
    which fastfetch >/dev/null 2>&1 && guarded_rm_rf "$4"

}

# Install base deep learning projects' required packages into a virtualenv
# Usage: ensure_base_dl_virtualenv <deep_learning_virtenv_dirpath> <rocm_ver_string> \
#            <torch_specific_requirements_txt_path> <non_torch_requirements_txt_path> \
#            <torchcodec_ver_str>
ensure_base_dl_virtualenv() {

    test -d "$1" && guarded_rm_rf "$1"
    virtualenv "$1"
    # Parameterized source since this function encapsulate setup logic invariants
    # shellcheck disable=SC1090,SC1091
    . "$1/bin/activate"
    pip install --upgrade pip
    pip install --requirement "$3" --index-url "https://download.pytorch.org/whl/rocm$2"
    pip install "torchcodec==$5" --index-url="https://download.pytorch.org/whl/cpu"
    pip install --requirement "$4"
    deactivate

}

# Install GPGPU python arrays projects' required packages into a virtualenv
# Usage: ensure_gpu_arr_virtualenv <gpu_arr_virtenv_dirpath> <cloned_cupy_dirpath> \
#            <non_cupy_requirements_txt_path> <cupy_version_tag> <cupy_build_log_path>
ensure_gpu_arr_virtualenv() {

    _gfx11_fallback_arch="gfx1100"
    test -d "$1" && guarded_rm_rf "$1"
    virtualenv "$1"
    # Parameterized source since this function encapsulate setup logic invariants
    # shellcheck disable=SC1090,SC1091
    . "$1/bin/activate"
    pip install --upgrade pip
    pip install --requirement "$3"
    test -d "$2" && guarded_rm_rf "$2"
    git clone https://github.com/cupy/cupy.git "$2"
    git -C "$2" -c advice.detachedHead=false checkout "$4"
    git -C "$2" submodule update --init --recursive
    ROCM_HOME="$(hipconfig --rocmpath | cut --delimiter="-" --fields=1)" || {
        echo "FAILED to detect 'ROCM_HOME'!" >&2
        exit 1
    }
    HCC_AMDGPU_TARGET="$(detect_amd_smi_gpu_arch 0)" || {
        echo "FAILED to detect GFX Version of ROCm device 0!" >&2
        exit 1
    }
    # Note: logic inside this if statement assumes that 'HCC_AMDGPU_TARGET' contains ONLY ONE
    #     valid 'amdgpu' HIP arch
    if [ "${CUPY_BUILD_GFX11_FALLBACK:-0}" -eq 1 ]; then
        if [ "${HCC_AMDGPU_TARGET}" = "${_gfx11_fallback_arch}" ]; then
            echo "Building for '${_gfx11_fallback_arch}' as fallback arch requested," \
                                                        "but '${_gfx11_fallback_arch}' is" >&2
            echo "    already 'native' arch! NOT proceeding to modify 'HCC_AMDGPU_TARGET'" >&2
            echo "    for building CuPy..." >&2
        elif echo "${HCC_AMDGPU_TARGET}" | grep --quiet "^gfx1101$"; then
            echo "Building for '${_gfx11_fallback_arch}' as fallback arch requested," \
                                                                    "and 'native' arch"
            echo "    is supported RDNA 3 non-'${_gfx11_fallback_arch}' arch; " \
                                               "appending '${_gfx11_fallback_arch}' to"
            echo "    'HCC_AMDGPU_TARGET'..."
            HCC_AMDGPU_TARGET="${HCC_AMDGPU_TARGET},${_gfx11_fallback_arch}"
        else
            echo "WARNING: Building for '${_gfx11_fallback_arch}' as fallback arch" >&2
            echo "    requested, but 'native' arch of '${HCC_AMDGPU_TARGET}' is NOT" >&2
            echo "    a compatible and/or supported option! NOT proceeding to modify" >&2
            echo "    'HCC_AMDGPU_TARGET' for building CuPy..." >&2
        fi
    fi
    CUPY_NUM_BUILD_JOBS="$(nproc)"
    echo "GOT: ROCM_HOME='${ROCM_HOME}', HCC_AMDGPU_TARGET='${HCC_AMDGPU_TARGET}'," \
        "CUPY_NUM_BUILD_JOBS='${CUPY_NUM_BUILD_JOBS}'"
    export ROCM_HOME
    export HCC_AMDGPU_TARGET
    export CUPY_NUM_BUILD_JOBS
    export CUPY_INSTALL_USE_HIP=1
    if ! : > "$5"; then
        echo "FAILED to initialize CuPy build log at '$5'!" >&2
        return 1
    fi
    echo "Building CuPy wheel; verbose build log: '$5'"
    if pip --log "$5" wheel --wheel-dir "$2/dist" "$2"; then
        echo "CuPy wheel build completed; verbose build log: '$5'"
    else
        _cupy_wheel_status="$?"
        echo "FAILED to build CuPy wheel; verbose build log: '$5'" >&2
        echo "--- Last ${_CUPY_BUILD_LOG_TAIL_LINES} lines of CuPy build log ---" >&2
        if ! tail --lines="${_CUPY_BUILD_LOG_TAIL_LINES}" "$5" >&2; then
            echo "WARNING: unable to print CuPy build log tail!" >&2
        fi
        return "${_cupy_wheel_status}"
    fi
    if pip install "$2/dist"/cupy*.whl; then
        guarded_rm_rf "$2"
    else
        _cupy_install_status="$?"
        echo "FAILED to install the built CuPy wheel!" >&2
        echo "    Preserving CuPy checkout '$2' and build log '$5'." >&2
        return "${_cupy_install_status}"
    fi
    deactivate

}

# Install ComfyUI's required packages into a virtualenv
# Usage: ensure_comfyui_virtualenv <deep_learning_virtenv_dirpath> <comfyui_clone_dir_path> \
#            <comfyui_version_tag> <torch_specific_requirements_txt_path> <non_torch_requirements_txt_path> \
#            <before_comfyui_install_pip_freeze_path> <after_comfyui_install_pip_freeze_path>
ensure_comfyui_virtualenv() {

    test -d "$2" && guarded_rm_rf "$2"
    git clone https://github.com/Comfy-Org/ComfyUI.git "$2"
    git -C "$2" -c advice.detachedHead=false checkout "$3"
    git -C "$2" submodule update --init --recursive
    # Parameterized source since this function encapsulate setup logic invariants
    # shellcheck disable=SC1090,SC1091
    . "$1/bin/activate"
    pip check
    pip freeze > "$6"
    pip install --requirement "$2/requirements.txt" --requirement "$5" --constraint "$4"
    pip check
    pip freeze > "$7"
    deactivate

}
