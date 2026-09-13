# shellcheck shell=bash

_amd_devcloud_amdgpu_module_is_loaded() {
    [ -d /sys/module/amdgpu ]
}

_amd_devcloud_kfd_is_present() {
    [ -e /dev/kfd ] || [ -L /dev/kfd ]
}

_amd_devcloud_collect_command_artifacts() {
    local _command_name

    for _command_name in "${AMD_DEVCLOUD_ADMISSION_COMMAND_SENTINELS[@]}"; do
        if command -v "${_command_name}" >/dev/null 2>&1; then
            printf '%s\n' "${_command_name}"
        fi
    done
}

_amd_devcloud_collect_path_artifacts() {
    local _path

    for _path in "${AMD_DEVCLOUD_ADMISSION_PATH_SENTINELS[@]}"; do
        if [ -e "${_path}" ] || [ -L "${_path}" ]; then
            printf '%s\n' "${_path}"
        fi
    done
}

# Check for the exact bare AMD DevCloud stack state and internally consistent
#     system-upgrade milestone state before ordinary-user setup mutation.
# Usage: check_amd_devcloud_system_upgrade_admission_dont_wrap <milestones_directory>
# Returns: 0 for plan-only or accepted bare state; 1 for failed observations,
#          selected stack artifacts, or contradictory system-upgrade markers
check_amd_devcloud_system_upgrade_admission_dont_wrap() {
    local _milestones_dir
    local _milestones_parent
    local _upgrade_marker
    local _reboot_pending_marker
    local _reboot_done_marker
    local _pci_output
    local _pci_count=0
    local _pci_line
    local _package_output
    local _package_name
    local _package_status
    local _package_sentinel
    local _command_artifacts
    local _path_artifacts
    local _amdgpu_loaded=0
    local _kfd_present=0
    local _stage_marker
    local -a _package_artifacts=()
    local -a _stage_markers=()

    if [ "$#" -ne 1 ]; then
        echo "ERROR: DevCloud system-upgrade admission expects one milestones directory!" >&2
        return 1
    fi
    _milestones_dir="$1"

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would require the finite AMD DevCloud bare-stack"
        echo "[PLAN ONLY]     sentinels and consistent system-upgrade milestones."
        return 0
    fi

    if [ -e "${_milestones_dir}" ] || [ -L "${_milestones_dir}" ]; then
        if [ ! -d "${_milestones_dir}" ] || [ -L "${_milestones_dir}" ]; then
            echo "ERROR: DevCloud milestones path '${_milestones_dir}'" >&2
            echo "    exists but is not a real directory!" >&2
            return 1
        fi
    else
        _milestones_parent="${_milestones_dir%/*}"
        if [ "${_milestones_parent}" = "${_milestones_dir}" ]; then
            _milestones_parent="."
        fi
        if [ ! -d "${_milestones_parent}" ] ||
            [ ! -x "${_milestones_parent}" ]; then
            echo "ERROR: DevCloud milestones parent '${_milestones_parent}'" >&2
            echo "    is unavailable or inaccessible!" >&2
            return 1
        fi
    fi
    if ! command -v lspci >/dev/null 2>&1 ||
        ! command -v dpkg-query >/dev/null 2>&1; then
        echo "ERROR: DevCloud admission requires 'lspci' and 'dpkg-query'!" >&2
        return 1
    fi

    if ! _pci_output="$(lspci -Dn -d \
        "${AMD_DEVCLOUD_EXPECTED_BARE_PCI_DEVICE_ID}")"; then
        echo "ERROR: unable to inspect the expected AMD PCI device!" >&2
        return 1
    fi
    while IFS= read -r _pci_line; do
        if [ -n "${_pci_line}" ]; then
            _pci_count=$((_pci_count + 1))
        fi
    done <<< "${_pci_output}"

    if ! _package_output="$(dpkg-query --show \
        --showformat='${Package}\t${db:Status-Status}\n')"; then
        echo "ERROR: unable to inspect installed package state!" >&2
        return 1
    fi
    while IFS=$'\t' read -r _package_name _package_status; do
        for _package_sentinel in \
            "${AMD_DEVCLOUD_ADMISSION_PACKAGE_SENTINELS[@]}"; do
            if [ "${_package_name}" = "${_package_sentinel}" ]; then
                _package_artifacts+=("${_package_name} (${_package_status})")
            fi
        done
    done <<< "${_package_output}"

    _command_artifacts="$(_amd_devcloud_collect_command_artifacts)"
    _path_artifacts="$(_amd_devcloud_collect_path_artifacts)"
    if _amd_devcloud_amdgpu_module_is_loaded; then
        _amdgpu_loaded=1
    fi
    if _amd_devcloud_kfd_is_present; then
        _kfd_present=1
    fi

    _upgrade_marker="${_milestones_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done"
    _reboot_pending_marker="${_milestones_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.pending"
    _reboot_done_marker="${_milestones_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done"
    for _stage_marker in "${_upgrade_marker}" "${_reboot_pending_marker}" \
        "${_reboot_done_marker}"; do
        if [ -e "${_stage_marker}" ] || [ -L "${_stage_marker}" ]; then
            if [ ! -f "${_stage_marker}" ] || [ -L "${_stage_marker}" ]; then
                echo "ERROR: unexpected DevCloud system-upgrade marker type:" >&2
                echo "    ${_stage_marker}" >&2
                return 1
            fi
            _stage_markers+=("${_stage_marker}")
        fi
    done
    if { [ -e "${_reboot_pending_marker}" ] ||
            [ -e "${_reboot_done_marker}" ]; } &&
        [ ! -f "${_upgrade_marker}" ]; then
        echo "ERROR: DevCloud reboot state exists without a completed upgrade!" >&2
        return 1
    fi
    if [ -e "${_reboot_pending_marker}" ] && [ -e "${_reboot_done_marker}" ]; then
        echo "ERROR: DevCloud system-upgrade reboot is both pending and complete!" >&2
        return 1
    fi

    if [ "${_pci_count}" -ne 1 ] || [ "${_amdgpu_loaded}" -eq 1 ] ||
        [ "${_kfd_present}" -eq 1 ] ||
        [ "${#_package_artifacts[@]}" -ne 0 ] ||
        [ -n "${_command_artifacts}" ] || [ -n "${_path_artifacts}" ]; then
        echo "ERROR: AMD DevCloud admission state is unknown; refusing mutation." >&2
        echo "Expected PCI device count: 1; observed: ${_pci_count}" >&2
        if [ "${_amdgpu_loaded}" -eq 1 ]; then
            echo "Loaded amdgpu module detected." >&2
        fi
        if [ "${_kfd_present}" -eq 1 ]; then
            echo "/dev/kfd detected." >&2
        fi
        if [ "${#_package_artifacts[@]}" -ne 0 ]; then
            printf 'Selected package artifact: %s\n' \
                "${_package_artifacts[@]}" >&2
        fi
        if [ -n "${_command_artifacts}" ]; then
            printf 'Selected command artifacts:\n%s\n' \
                "${_command_artifacts}" >&2
        fi
        if [ -n "${_path_artifacts}" ]; then
            printf 'Selected path artifacts:\n%s\n' "${_path_artifacts}" >&2
        fi
        return 1
    fi

    echo "AMD DevCloud admission state: ${AMD_DEVCLOUD_ADMISSION_BARE}"
    if [ "${#_stage_markers[@]}" -gt 0 ]; then
        printf 'Recognized system-upgrade marker: %s\n' "${_stage_markers[@]}"
    fi
}
