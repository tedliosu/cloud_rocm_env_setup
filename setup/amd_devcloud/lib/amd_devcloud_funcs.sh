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

_amd_devcloud_expected_repository_bootstrap_command_artifacts() {
    printf '%s\n' \
        "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_COMMAND_ARTIFACTS[@]}"
}

_amd_devcloud_expected_repository_bootstrap_path_artifacts() {
    printf '%s\n' "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PATH_ARTIFACTS[@]}"
}

# Classify the finite accepted AMD DevCloud setup states and require internally
#     consistent stage milestones before ordinary-user setup mutation.
# Usage: check_amd_devcloud_setup_admission_dont_wrap <milestones_directory>
# Returns: 0 for plan-only, accepted bare state, or the exact project-installed
#          repository bootstrap; 1 for failed observations or unknown state
check_amd_devcloud_setup_admission_dont_wrap() {
    local _milestones_dir
    local _milestones_parent
    local _upgrade_marker
    local _tmux_marker
    local _reboot_pending_marker
    local _reboot_done_marker
    local _repository_bootstrap_marker
    local _pci_output
    local _pci_count=0
    local _pci_line
    local _package_output
    local _package_name
    local _package_status
    local _package_version
    local _package_sentinel
    local _command_artifacts
    local _expected_command_artifacts
    local _path_artifacts
    local _expected_path_artifacts
    local _expected_package_artifact
    local _admission_state=""
    local _amdgpu_loaded=0
    local _kfd_present=0
    local _stage_marker
    local -a _package_artifacts=()
    local -a _stage_markers=()

    if [ "$#" -ne 1 ]; then
        echo "ERROR: DevCloud setup admission expects one milestones directory!" >&2
        return 1
    fi
    _milestones_dir="$1"

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would require a finite accepted AMD DevCloud stack state"
        echo "[PLAN ONLY]     and consistent setup milestones."
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
        --showformat='${Package}\t${db:Status-Status}\t${Version}\n')"; then
        echo "ERROR: unable to inspect installed package state!" >&2
        return 1
    fi
    while IFS=$'\t' read -r _package_name _package_status _package_version; do
        for _package_sentinel in \
            "${AMD_DEVCLOUD_ADMISSION_PACKAGE_SENTINELS[@]}"; do
            if [ "${_package_name}" = "${_package_sentinel}" ]; then
                _package_artifacts+=("${_package_name} (${_package_status}, ${_package_version})")
            fi
        done
    done <<< "${_package_output}"

    _command_artifacts="$(_amd_devcloud_collect_command_artifacts)"
    _path_artifacts="$(_amd_devcloud_collect_path_artifacts)"
    _expected_command_artifacts="$(_amd_devcloud_expected_repository_bootstrap_command_artifacts)"
    _expected_path_artifacts="$(_amd_devcloud_expected_repository_bootstrap_path_artifacts)"
    _expected_package_artifact="amdgpu-install (installed, ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION})"
    if _amd_devcloud_amdgpu_module_is_loaded; then
        _amdgpu_loaded=1
    fi
    if _amd_devcloud_kfd_is_present; then
        _kfd_present=1
    fi

    _upgrade_marker="${_milestones_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}.done"
    _tmux_marker="${_milestones_dir}/${AMD_DEVCLOUD_TMUX_STAGE_NAME}.done"
    _reboot_pending_marker="${_milestones_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.pending"
    _reboot_done_marker="${_milestones_dir}/${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}.done"
    _repository_bootstrap_marker="${_milestones_dir}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME}.done"
    for _stage_marker in "${_upgrade_marker}" "${_tmux_marker}" \
        "${_reboot_pending_marker}" "${_reboot_done_marker}" \
        "${_repository_bootstrap_marker}"; do
        if [ -e "${_stage_marker}" ] || [ -L "${_stage_marker}" ]; then
            if [ ! -f "${_stage_marker}" ] || [ -L "${_stage_marker}" ]; then
                echo "ERROR: unexpected DevCloud setup marker type:" >&2
                echo "    ${_stage_marker}" >&2
                return 1
            fi
            _stage_markers+=("${_stage_marker}")
        fi
    done
    if [ -e "${_tmux_marker}" ] && [ ! -f "${_upgrade_marker}" ]; then
        echo "ERROR: DevCloud tmux state exists without a completed upgrade!" >&2
        return 1
    fi
    if { [ -e "${_reboot_pending_marker}" ] ||
            [ -e "${_reboot_done_marker}" ]; } &&
        [ ! -f "${_tmux_marker}" ]; then
        echo "ERROR: DevCloud reboot state exists without completed tmux setup!" >&2
        return 1
    fi
    if [ -e "${_reboot_pending_marker}" ] && [ -e "${_reboot_done_marker}" ]; then
        echo "ERROR: DevCloud system-upgrade reboot is both pending and complete!" >&2
        return 1
    fi
    if [ -e "${_repository_bootstrap_marker}" ] &&
        [ ! -f "${_reboot_done_marker}" ]; then
        echo "ERROR: DevCloud repository-bootstrap state exists before the" >&2
        echo "    system-upgrade reboot was acknowledged!" >&2
        return 1
    fi

    if [ "${_pci_count}" -eq 1 ] && [ "${_amdgpu_loaded}" -eq 0 ] &&
        [ "${_kfd_present}" -eq 0 ]; then
        if [ ! -e "${_repository_bootstrap_marker}" ] &&
            [ "${#_package_artifacts[@]}" -eq 0 ] &&
            [ -z "${_command_artifacts}" ] && [ -z "${_path_artifacts}" ]; then
            _admission_state="${AMD_DEVCLOUD_ADMISSION_BARE}"
        elif [ -f "${_repository_bootstrap_marker}" ] &&
            [ "${#_package_artifacts[@]}" -eq 1 ] &&
            [ "${_package_artifacts[0]}" = "${_expected_package_artifact}" ] &&
            [ "${_command_artifacts}" = "${_expected_command_artifacts}" ] &&
            [ "${_path_artifacts}" = "${_expected_path_artifacts}" ]; then
            _admission_state="${AMD_DEVCLOUD_ADMISSION_REPOSITORY_BOOTSTRAP}"
        fi
    fi

    if [ -z "${_admission_state}" ]; then
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

    echo "AMD DevCloud admission state: ${_admission_state}"
    if [ "${#_stage_markers[@]}" -gt 0 ]; then
        printf 'Recognized setup marker: %s\n' "${_stage_markers[@]}"
    fi
}

# Download, verify, install, and confirm the pinned AMD repository-bootstrap
#     package for the adopted DevCloud ROCm generation.
# Usage: no arguments required
# Returns: 0 after exact package installation; 1 on failed download,
#          verification, installation, or post-install package-state checks
install_amd_devcloud_repository_bootstrap() (
    local _temp_dir
    local _package_path
    local _package_version
    local _installed_state
    local _command_artifacts
    local _expected_command_artifacts
    local _path_artifacts
    local _expected_path_artifacts
    local _required_command

    if [ "$#" -ne 0 ]; then
        echo "ERROR: AMD repository bootstrap expects no arguments!" >&2
        return 1
    fi
    for _required_command in apt-get dpkg-deb dpkg-query mktemp rmdir rm \
        sha256sum sudo wget; do
        if ! command -v "${_required_command}" >/dev/null 2>&1; then
            echo "ERROR: repository bootstrap requires '${_required_command}'!" >&2
            return 1
        fi
    done

    if ! _temp_dir="$(mktemp --directory \
        --tmpdir amd-devcloud-repository-bootstrap.XXXXXX)"; then
        echo "ERROR: unable to create repository-bootstrap temporary directory!" >&2
        return 1
    fi
    _package_path="${_temp_dir}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_FILENAME}"
    trap 'rm --force -- "${_package_path}"; rmdir -- "${_temp_dir}" || :' EXIT

    echo "Downloading pinned AMD repository-bootstrap package..."
    if ! wget --tries=3 --timeout=30 --output-document="${_package_path}" \
        "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}"; then
        echo "ERROR: unable to download the pinned AMD repository bootstrap!" >&2
        return 1
    fi
    if ! printf '%s  %s\n' "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_SHA256}" \
        "${_package_path}" | sha256sum --check --status; then
        echo "ERROR: AMD repository-bootstrap SHA-256 verification failed!" >&2
        return 1
    fi
    if ! _package_version="$(dpkg-deb --field "${_package_path}" Version)"; then
        echo "ERROR: unable to inspect repository-bootstrap package metadata!" >&2
        return 1
    fi
    if [ "${_package_version}" != \
        "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}" ]; then
        echo "ERROR: unexpected AMD repository-bootstrap package version" >&2
        echo "    '${_package_version}'!" >&2
        return 1
    fi

    if ! sudo --set-home apt-get install --assume-yes "${_package_path}"; then
        echo "ERROR: unable to install the AMD repository-bootstrap package!" >&2
        return 1
    fi
    if ! sudo --set-home apt-get update \
        --option=APT::Update::Error-Mode=any; then
        echo "ERROR: AMD repository bootstrap installed, but refreshing" >&2
        echo "    metadata from its configured repositories failed!" >&2
        return 1
    fi
    if ! _installed_state="$(dpkg-query --show \
        --showformat='${db:Status-Status}\t${Version}\n' amdgpu-install)"; then
        echo "ERROR: unable to inspect installed repository-bootstrap state!" >&2
        return 1
    fi
    if [ "${_installed_state}" != \
        $'installed\t'"${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}" ]; then
        echo "ERROR: installed AMD repository-bootstrap state is unexpected:" >&2
        echo "    ${_installed_state}" >&2
        return 1
    fi

    _command_artifacts="$(_amd_devcloud_collect_command_artifacts)"
    _expected_command_artifacts="$(_amd_devcloud_expected_repository_bootstrap_command_artifacts)"
    if [ "${_command_artifacts}" != "${_expected_command_artifacts}" ]; then
        echo "ERROR: repository bootstrap did not install the exact expected" >&2
        echo "    command artifacts!" >&2
        if [ -n "${_command_artifacts}" ]; then
            printf 'Observed command artifacts:\n%s\n' \
                "${_command_artifacts}" >&2
        fi
        return 1
    fi

    _path_artifacts="$(_amd_devcloud_collect_path_artifacts)"
    _expected_path_artifacts="$(_amd_devcloud_expected_repository_bootstrap_path_artifacts)"
    if [ "${_path_artifacts}" != "${_expected_path_artifacts}" ]; then
        echo "ERROR: repository bootstrap did not install the exact expected" >&2
        echo "    filesystem artifacts!" >&2
        if [ -n "${_path_artifacts}" ]; then
            printf 'Observed path artifacts:\n%s\n' "${_path_artifacts}" >&2
        fi
        return 1
    fi

    echo "Pinned AMD repository-bootstrap package installed and verified."
)

# Install and confirm the pinned AMDGPU DKMS and versioned AMD SMI packages,
#     including the packages required to build for the running Ubuntu kernel.
# Usage: no arguments required
# Returns: 0 after exact package installation; 1 on failed kernel observation,
#          installation, or post-install package-state checks
install_amd_devcloud_driver() (
    local _kernel_release
    local _headers_package
    local _modules_extra_package
    local _package_state
    local _kernel_package
    local _required_command

    if [ "$#" -ne 0 ]; then
        echo "ERROR: AMD DevCloud driver installation expects no arguments!" >&2
        return 1
    fi
    for _required_command in apt-get dpkg-query sudo uname; do
        if ! command -v "${_required_command}" >/dev/null 2>&1; then
            echo "ERROR: driver installation requires '${_required_command}'!" >&2
            return 1
        fi
    done

    if ! _kernel_release="$(uname --kernel-release)" ||
        [ -z "${_kernel_release}" ]; then
        echo "ERROR: unable to determine the running kernel release!" >&2
        return 1
    fi
    _headers_package="linux-headers-${_kernel_release}"
    _modules_extra_package="linux-modules-extra-${_kernel_release}"

    if ! sudo --set-home env DEBIAN_FRONTEND="noninteractive" \
        NEEDRESTART_MODE="a" apt-get install --assume-yes \
        "${_headers_package}" "${_modules_extra_package}"; then
        echo "ERROR: unable to install packages for the running kernel!" >&2
        return 1
    fi
    if ! sudo --set-home env DEBIAN_FRONTEND="noninteractive" \
        NEEDRESTART_MODE="a" apt-get install --assume-yes \
        "${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}=${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}" \
        "${AMD_DEVCLOUD_AMD_SMI_PACKAGE}=${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}"; then
        echo "ERROR: unable to install the pinned AMD DevCloud driver stack!" >&2
        return 1
    fi

    for _kernel_package in "${_headers_package}" "${_modules_extra_package}"; do
        if ! _package_state="$(dpkg-query --show \
            --showformat='${db:Status-Status}\t${Version}\n' \
            "${_kernel_package}")" ||
            [ "${_package_state}" = "${_package_state#*$'\t'}" ] ||
            [ "${_package_state%%$'\t'*}" != "installed" ] ||
            [ -z "${_package_state#*$'\t'}" ]; then
            echo "ERROR: required running-kernel package state is unexpected:" >&2
            echo "    ${_kernel_package}: ${_package_state}" >&2
            return 1
        fi
    done

    if ! _package_state="$(dpkg-query --show \
        --showformat='${db:Status-Status}\t${Version}\n' \
        "${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}")" ||
        [ "${_package_state}" != \
            $'installed\t'"${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}" ]; then
        echo "ERROR: installed AMDGPU DKMS package state is unexpected:" >&2
        echo "    ${_package_state}" >&2
        return 1
    fi
    if ! _package_state="$(dpkg-query --show \
        --showformat='${db:Status-Status}\t${Version}\n' \
        "${AMD_DEVCLOUD_AMD_SMI_PACKAGE}")" ||
        [ "${_package_state}" != \
            $'installed\t'"${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}" ]; then
        echo "ERROR: installed versioned AMD SMI package state is unexpected:" >&2
        echo "    ${_package_state}" >&2
        return 1
    fi

    echo "Pinned AMDGPU DKMS and versioned AMD SMI packages installed."
)
