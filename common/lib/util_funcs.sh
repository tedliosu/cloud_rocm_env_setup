
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

