
# Helper function to run a stage
# Usage: run_stage <milestones_directory> <function_to_run> [function_arguments]...
run_stage() {

    _milestones_dir="$1"
    shift
    _func_to_run="$1"
    shift
    _done_marker_file="${_milestones_dir}/${_func_to_run}.done"

    if [ ! -f "${_done_marker_file}" ]; then
        echo "--- starting stage: ${_func_to_run} ---"
        "${_func_to_run}" "$@" && touch "${_done_marker_file}"
        echo "--- completed stage: ${_func_to_run} ---"
    else
        echo "--- skipping stage: ${_func_to_run} (already complete) ---"
    fi

}

# System update (no kernel update by default)
# Usage: no arguments required
apt_get_sys_update() {
    sudo --set-home apt-get update
    sudo --set-home apt-get upgrade --assume-yes
}

# Reboot once helper (for ONLY after a system update)
# Usage: reboot_once_dont_wrap <milestones_directory>
reboot_once_dont_wrap() {
    reboot_marker_file="$1/reboot_once_dont_wrap.done"
    if [ ! -f "$reboot_marker_file" ]; then
        echo "Reboot required, performing ONE reboot..."
        touch "$reboot_marker_file"
        sudo --set-home reboot
        exit 0
    else
        echo "--- skipping stage: reboot_once_dont_wrap (already complete) ---"
    fi
}

# up-to-date CMake setup, assuming Ubuntu
# Usage: ensure_latest_cmake <ubuntu_distro_codename>
ensure_latest_cmake() {

    _kitware_test_file="/usr/share/doc/kitware-archive-keyring/copyright"
    _kitware_signing_file="/usr/share/keyrings/kitware-archive-keyring.gpg"
    _signed_by_str="[signed-by=${_kitware_signing_file}]"
    sudo --set-home apt-get install ca-certificates gpg wget
    test -f "${_kitware_test_file}" ||
        wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null |
            gpg --dearmor - | sudo --set-home tee "${_kitware_signing_file}" >/dev/null
    echo "deb ${_signed_by_str} https://apt.kitware.com/ubuntu/ $1 main" |
        sudo --set-home tee /etc/apt/sources.list.d/kitware.list >/dev/null
    sudo --set-home apt-get update
    test -f "${_kitware_test_file}" || sudo --set-home rm "${_kitware_signing_file}"
    sudo --set-home apt-get install kitware-archive-keyring
    sudo --set-home apt-get install cmake
   
}

# Download and configure apt packages with custom settings, assuming Ubuntu
# Usage: ensure_apt_with_custom_conf <path_to_common_apt_packages_list>
ensure_apt_with_custom_conf() {

    _common_apt_packages="$(<"$1" tr "\n" " " | sed 's/ *$//g')"
    _curr_username="$(whoami)"
    _curr_home_dir="/home/${_curr_username}"
    if [ "${_curr_username}" = "root" ]; then
        _curr_home_dir="/root"
    fi
    _w3m_hidden_dir="${_curr_home_dir}/.w3m"
    mkdir --parent "${_w3m_hidden_dir}"
    touch "${_w3m_hidden_dir}/history"
    # safe because apt package names each NEVER contain whitespace(s)
    # shellcheck disable=SC2086
    sudo --set-home apt-get install ${_common_apt_packages} w3m apt-file
    sudo --set-home apt-file update
    sudo --set-home update-alternatives --set "pager" "/usr/bin/w3m"

}

