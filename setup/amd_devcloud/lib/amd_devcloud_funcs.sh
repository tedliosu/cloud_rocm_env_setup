# shellcheck shell=bash

_amd_devcloud_amdgpu_module_is_loaded() {
    [ -d /sys/module/amdgpu ]
}

_amd_devcloud_kfd_is_present() {
    [ -e /dev/kfd ] || [ -L /dev/kfd ]
}

_amd_devcloud_amd_smi_is_executable() {
    [ -x "${AMD_DEVCLOUD_AMD_SMI_PATH}" ] &&
        [ ! -d "${AMD_DEVCLOUD_AMD_SMI_PATH}" ]
}

_amd_devcloud_rocm_alternative_matches_versioned_root() {
    local _resolved_rocm_alternative

    [ -L "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}" ] || return 1
    if ! _resolved_rocm_alternative="$(readlink --canonicalize-existing \
        "${AMD_DEVCLOUD_ROCM_ALTERNATIVE_PATH}")"; then
        return 1
    fi
    [ "${_resolved_rocm_alternative}" = "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}" ]
}

_amd_devcloud_run_amd_smi_static() {
    "${AMD_DEVCLOUD_AMD_SMI_PATH}" static \
        --gpu "${AMD_DEVCLOUD_EXPECTED_GPU_INDEX}" --asic --driver --json
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

_amd_devcloud_expected_driver_path_artifacts() {
    printf '%s\n' "${AMD_DEVCLOUD_DRIVER_PATH_ARTIFACTS[@]}"
}

# Classify the finite accepted AMD DevCloud setup states and require internally
#     consistent stage milestones before ordinary-user setup mutation.
# Usage: check_amd_devcloud_setup_admission_dont_wrap <milestones_directory>
# Returns: 0 for plan-only or an exact accepted bare, repository-bootstrap,
#          driver-installed, or ROCm-userland state; 1 otherwise
check_amd_devcloud_setup_admission_dont_wrap() {
    local _milestones_dir
    local _milestones_parent
    local _upgrade_marker
    local _tmux_marker
    local _reboot_pending_marker
    local _reboot_done_marker
    local _repository_bootstrap_marker
    local _driver_marker
    local _driver_reboot_pending_marker
    local _driver_reboot_done_marker
    local _rocm_userland_marker
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
    local _expected_driver_path_artifacts
    local _expected_driver_command_artifacts
    local _expected_driver_path_command_artifacts
    local _repository_commands_present=0
    local _admission_state=""
    local _amdgpu_loaded=0
    local _kfd_present=0
    local _stage_marker
    local -A _package_artifacts=()
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
                _package_artifacts["${_package_name}"]="${_package_status}"$'\t'"${_package_version}"
            fi
        done
    done <<< "${_package_output}"

    _command_artifacts="$(_amd_devcloud_collect_command_artifacts)"
    _path_artifacts="$(_amd_devcloud_collect_path_artifacts)"
    _expected_command_artifacts="$(_amd_devcloud_expected_repository_bootstrap_command_artifacts)"
    _expected_path_artifacts="$(_amd_devcloud_expected_repository_bootstrap_path_artifacts)"
    _expected_package_artifact=$'installed\t'"${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}"
    _expected_driver_path_artifacts="$(_amd_devcloud_expected_driver_path_artifacts)"
    _expected_driver_command_artifacts="${_expected_command_artifacts}"
    _expected_driver_path_command_artifacts="${_expected_command_artifacts}"$'\n'"amd-smi"
    # Collection follows the finite sentinel order. Once the complete ROCm
    #     metapackage is installed, its PATH-visible tools may extend this exact
    #     repository-bootstrap prefix without changing managed package state.
    case ${_command_artifacts} in
        "${_expected_command_artifacts}"|"${_expected_command_artifacts}"$'\n'*)
            _repository_commands_present=1
            ;;
    esac
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
    _driver_marker="${_milestones_dir}/${AMD_DEVCLOUD_DRIVER_STAGE_NAME}.done"
    _driver_reboot_pending_marker="${_milestones_dir}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.pending"
    _driver_reboot_done_marker="${_milestones_dir}/${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}.done"
    _rocm_userland_marker="${_milestones_dir}/${AMD_DEVCLOUD_ROCM_USERLAND_STAGE_NAME}.done"
    for _stage_marker in "${_upgrade_marker}" "${_tmux_marker}" \
        "${_reboot_pending_marker}" "${_reboot_done_marker}" \
        "${_repository_bootstrap_marker}" "${_driver_marker}" \
        "${_driver_reboot_pending_marker}" "${_driver_reboot_done_marker}" \
        "${_rocm_userland_marker}"; do
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
    if [ -e "${_driver_marker}" ] &&
        [ ! -f "${_repository_bootstrap_marker}" ]; then
        echo "ERROR: DevCloud driver state exists without a completed" >&2
        echo "    repository bootstrap!" >&2
        return 1
    fi
    if { [ -e "${_driver_reboot_pending_marker}" ] ||
            [ -e "${_driver_reboot_done_marker}" ]; } &&
        [ ! -f "${_driver_marker}" ]; then
        echo "ERROR: DevCloud driver-reboot state exists without a completed" >&2
        echo "    driver installation!" >&2
        return 1
    fi
    if [ -e "${_driver_reboot_pending_marker}" ] &&
        [ -e "${_driver_reboot_done_marker}" ]; then
        echo "ERROR: DevCloud driver reboot is both pending and complete!" >&2
        return 1
    fi
    if [ -e "${_rocm_userland_marker}" ] &&
        [ ! -f "${_driver_reboot_done_marker}" ]; then
        echo "ERROR: DevCloud ROCm userland state exists before the driver" >&2
        echo "    reboot was acknowledged!" >&2
        return 1
    fi

    # Keep the complete state fingerprints adjacent so their mutually exclusive
    #     marker and artifact requirements remain directly comparable.
    if [ "${_pci_count}" -eq 1 ]; then
        if [ "${_amdgpu_loaded}" -eq 0 ] && [ "${_kfd_present}" -eq 0 ] &&
            [ ! -e "${_repository_bootstrap_marker}" ] &&
            [ "${#_package_artifacts[@]}" -eq 0 ] &&
            [ -z "${_command_artifacts}" ] && [ -z "${_path_artifacts}" ]; then
            _admission_state="${AMD_DEVCLOUD_ADMISSION_BARE}"
        elif [ "${_amdgpu_loaded}" -eq 0 ] && [ "${_kfd_present}" -eq 0 ] &&
            [ -f "${_repository_bootstrap_marker}" ] &&
            [ ! -e "${_driver_marker}" ] &&
            [ "${#_package_artifacts[@]}" -eq 1 ] &&
            [ "${_package_artifacts[amdgpu-install]-}" = \
                "${_expected_package_artifact}" ] &&
            [ "${_command_artifacts}" = "${_expected_command_artifacts}" ] &&
            [ "${_path_artifacts}" = "${_expected_path_artifacts}" ]; then
            _admission_state="${AMD_DEVCLOUD_ADMISSION_REPOSITORY_BOOTSTRAP}"
        elif [ -f "${_driver_marker}" ] &&
            [ ! -e "${_rocm_userland_marker}" ] &&
            [ "${#_package_artifacts[@]}" -eq 4 ] &&
            [ "${_package_artifacts[amdgpu-install]-}" = \
                "${_expected_package_artifact}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_AMD_SMI_PACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_ROCM_CORE_PACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_ROCM_CORE_PACKAGE_VERSION}" ] &&
            { [ "${_command_artifacts}" = \
                    "${_expected_driver_command_artifacts}" ] ||
                [ "${_command_artifacts}" = \
                    "${_expected_driver_path_command_artifacts}" ]; } &&
            [ "${_path_artifacts}" = "${_expected_driver_path_artifacts}" ] &&
            _amd_devcloud_rocm_alternative_matches_versioned_root &&
            { { [ ! -e "${_driver_reboot_done_marker}" ] &&
                    [ "${_amdgpu_loaded}" -eq "${_kfd_present}" ]; } ||
                { [ -f "${_driver_reboot_done_marker}" ] &&
                    [ "${_amdgpu_loaded}" -eq 1 ] &&
                    [ "${_kfd_present}" -eq 1 ]; }; }; then
            _admission_state="${AMD_DEVCLOUD_ADMISSION_DRIVER_INSTALLED}"
        elif [ -f "${_rocm_userland_marker}" ] &&
            [ "${_amdgpu_loaded}" -eq 1 ] &&
            [ "${_kfd_present}" -eq 1 ] &&
            [ "${#_package_artifacts[@]}" -eq 5 ] &&
            [ "${_package_artifacts[amdgpu-install]-}" = \
                "${_expected_package_artifact}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_AMD_SMI_PACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_AMD_SMI_PACKAGE_VERSION}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_ROCM_CORE_PACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_ROCM_CORE_PACKAGE_VERSION}" ] &&
            [ "${_package_artifacts[${AMD_DEVCLOUD_ROCM_METAPACKAGE}]-}" = \
                $'installed\t'"${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}" ] &&
            [ "${_repository_commands_present}" -eq 1 ] &&
            [ "${_path_artifacts}" = "${_expected_driver_path_artifacts}" ] &&
            _amd_devcloud_rocm_alternative_matches_versioned_root; then
            _admission_state="${AMD_DEVCLOUD_ADMISSION_ROCM_USERLAND_INSTALLED}"
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
            for _package_name in "${!_package_artifacts[@]}"; do
                printf 'Selected package artifact: %s (%s)\n' \
                    "${_package_name}" "${_package_artifacts[${_package_name}]}" >&2
            done
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
    for _required_command in apt-get dpkg-query readlink sudo uname; do
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
    if ! _amd_devcloud_rocm_alternative_matches_versioned_root; then
        echo "ERROR: the ROCm alternative does not resolve to the expected" >&2
        echo "    versioned root '${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}'!" >&2
        return 1
    fi
    if ! _amd_devcloud_amd_smi_is_executable; then
        echo "ERROR: versioned AMD SMI command is not executable:" >&2
        echo "    ${AMD_DEVCLOUD_AMD_SMI_PATH}" >&2
        return 1
    fi

    echo "Pinned AMDGPU DKMS and versioned AMD SMI packages installed."
)

# Install and confirm the complete versioned ROCm userland metapackage for the
#     adopted DevCloud ROCm generation.
# Usage: no arguments required
# Returns: 0 after exact metapackage installation; 1 on failed installation or
#          unexpected package or versioned-root state
install_amd_devcloud_rocm_userland() (
    local _package_state
    local _required_command

    if [ "$#" -ne 0 ]; then
        echo "ERROR: AMD DevCloud ROCm userland installation expects no arguments!" >&2
        return 1
    fi
    for _required_command in apt-get dpkg-query sudo; do
        if ! command -v "${_required_command}" >/dev/null 2>&1; then
            echo "ERROR: ROCm userland installation requires '${_required_command}'!" >&2
            return 1
        fi
    done

    if ! sudo --set-home env DEBIAN_FRONTEND="noninteractive" \
        NEEDRESTART_MODE="a" apt-get install --assume-yes \
        "${AMD_DEVCLOUD_ROCM_METAPACKAGE}=${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}"; then
        echo "ERROR: unable to install the pinned AMD DevCloud ROCm userland!" >&2
        return 1
    fi
    if ! _package_state="$(dpkg-query --show \
        --showformat='${db:Status-Status}\t${Version}\n' \
        "${AMD_DEVCLOUD_ROCM_METAPACKAGE}")" ||
        [ "${_package_state}" != \
            $'installed\t'"${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}" ]; then
        echo "ERROR: installed ROCm metapackage state is unexpected:" >&2
        echo "    ${_package_state}" >&2
        return 1
    fi
    if ! _amd_devcloud_rocm_alternative_matches_versioned_root; then
        echo "ERROR: the ROCm alternative does not resolve to the expected" >&2
        echo "    versioned root '${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}'!" >&2
        return 1
    fi

    echo "Complete versioned ROCm userland metapackage installed."
)

# Install the observed packaged AMD RAPIDS workload environment from its
#     reviewed direct-requirements and resolver-options manifest.
# Usage: install_amd_devcloud_packaged_rapids_environment \
#            <virtualenv_directory> <requirements_file>
# Returns: 0 after installing and checking the reviewed packaged recipe; 1 on an
#          unexpected interpreter, incomplete inputs, or installation failure
install_amd_devcloud_packaged_rapids_environment() (
    local _virtualenv_dir
    local _requirements_file
    local _python_version

    if [ "$#" -ne 2 ]; then
        echo "ERROR: packaged AMD RAPIDS setup expects a virtualenv path" >&2
        echo "    and one requirements manifest!" >&2
        return 1
    fi
    _virtualenv_dir="$1"
    _requirements_file="$2"
    if [ ! -f "${_requirements_file}" ] ||
        [ ! -r "${_requirements_file}" ]; then
        echo "ERROR: packaged AMD RAPIDS requirements are not readable:" >&2
        echo "    ${_requirements_file}" >&2
        return 1
    fi
    if ! _python_version="$(python3 -c \
        'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" ||
        [ "${_python_version}" != "3.12" ]; then
        echo "ERROR: packaged AMD RAPIDS setup requires Python 3.12;" >&2
        echo "    observed '${_python_version:-unknown}'!" >&2
        return 1
    fi

    if [ -e "${_virtualenv_dir}" ] || [ -L "${_virtualenv_dir}" ]; then
        guarded_rm_rf "${_virtualenv_dir}"
    fi
    virtualenv "${_virtualenv_dir}"
    # Intentional variable path sourcing; the subshell keeps activation local.
    # shellcheck disable=SC1090,SC1091
    . "${_virtualenv_dir}/bin/activate"
    pip install --upgrade pip
    pip install --requirement "${_requirements_file}"
    pip check

    echo "Installed packaged AMD RAPIDS environment from requirements manifest."
)

# Add the one permitted persistent ROCm environment selection: an exact
#     versioned bin directory in the dedicated DevCloud user's PATH.
# Usage: ensure_amd_devcloud_rocm_path_profile_dont_wrap <home_directory>
# Returns: 0 after creating or recognizing the exact block; 1 for an invalid
#          home/profile or conflicting project-owned marker state
ensure_amd_devcloud_rocm_path_profile_dont_wrap() (
    local _home_dir
    local _profile_path
    local _profile_content=""
    local _profile_line
    local _profile_block
    local _profile_owner
    local _expected_owner
    local _begin_marker_count=0
    local _end_marker_count=0
    local _temp_path=""
    local _required_command

    if [ "$#" -ne 1 ]; then
        echo "ERROR: AMD DevCloud ROCm PATH setup expects one home directory!" >&2
        return 1
    fi
    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would ensure the exact versioned ROCm PATH profile block."
        return 0
    fi
    _home_dir="$1"
    if [ ! -d "${_home_dir}" ] || [ -L "${_home_dir}" ] ||
        [ ! -w "${_home_dir}" ] || [ ! -x "${_home_dir}" ]; then
        echo "ERROR: ROCm PATH setup requires a writable real home directory:" >&2
        echo "    ${_home_dir}" >&2
        return 1
    fi
    for _required_command in chmod cp id mktemp mv rm stat; do
        if ! command -v "${_required_command}" >/dev/null 2>&1; then
            echo "ERROR: ROCm PATH setup requires '${_required_command}'!" >&2
            return 1
        fi
    done

    _profile_path="${_home_dir}/.profile"
    # Preserve ${PATH} literally for evaluation when the profile is sourced.
    # shellcheck disable=SC2016
    _profile_block="$(printf '%s\nexport PATH="%s:${PATH}"\n%s' \
        "${AMD_DEVCLOUD_ROCM_PROFILE_BEGIN_MARKER}" \
        "${AMD_DEVCLOUD_ROCM_VERSIONED_BIN}" \
        "${AMD_DEVCLOUD_ROCM_PROFILE_END_MARKER}")"

    if [ -e "${_profile_path}" ] || [ -L "${_profile_path}" ]; then
        if [ ! -f "${_profile_path}" ] || [ -L "${_profile_path}" ] ||
            [ ! -r "${_profile_path}" ]; then
            echo "ERROR: '${_profile_path}' is not a readable regular file!" >&2
            return 1
        fi
        if ! _profile_owner="$(stat --format='%u:%g' "${_profile_path}")" ||
            ! _expected_owner="$(id --user):$(id --group)" ||
            [ "${_profile_owner}" != "${_expected_owner}" ]; then
            echo "ERROR: '${_profile_path}' is not owned by the current user" >&2
            echo "    and primary group!" >&2
            return 1
        fi
        _profile_content="$(<"${_profile_path}")"
        while IFS= read -r _profile_line || [ -n "${_profile_line}" ]; do
            case ${_profile_line} in
                "${AMD_DEVCLOUD_ROCM_PROFILE_BEGIN_MARKER}")
                    _begin_marker_count=$((_begin_marker_count + 1))
                    ;;
                "${AMD_DEVCLOUD_ROCM_PROFILE_END_MARKER}")
                    _end_marker_count=$((_end_marker_count + 1))
                    ;;
            esac
        done < "${_profile_path}"
    fi

    if [ "${_begin_marker_count}" -eq 1 ] &&
        [ "${_end_marker_count}" -eq 1 ]; then
        case ${_profile_content} in
            *"${_profile_block}"*)
                echo "Exact AMD DevCloud ROCm PATH profile block already present."
                return 0
                ;;
        esac
    fi
    if [ "${_begin_marker_count}" -ne 0 ] ||
        [ "${_end_marker_count}" -ne 0 ]; then
        echo "ERROR: conflicting AMD DevCloud ROCm PATH profile markers!" >&2
        return 1
    fi

    if ! _temp_path="$(mktemp --tmpdir="${_home_dir}" \
        .cloud-rocm-profile.XXXXXX)"; then
        echo "ERROR: unable to create a temporary profile file!" >&2
        return 1
    fi
    trap 'if [ -n "${_temp_path:-}" ]; then rm --force -- "${_temp_path}"; fi' EXIT

    if [ -e "${_profile_path}" ]; then
        if ! cp --preserve=mode,ownership -- \
            "${_profile_path}" "${_temp_path}"; then
            echo "ERROR: unable to prepare the existing profile update!" >&2
            return 1
        fi
        if [ -s "${_profile_path}" ]; then
            printf '\n' >> "${_temp_path}"
        fi
    elif ! chmod 0644 "${_temp_path}"; then
        echo "ERROR: unable to set the new profile mode!" >&2
        return 1
    fi
    if ! printf '%s\n' "${_profile_block}" >> "${_temp_path}"; then
        echo "ERROR: unable to write the AMD DevCloud ROCm PATH block!" >&2
        return 1
    fi
    if ! mv --no-target-directory -- "${_temp_path}" "${_profile_path}"; then
        echo "ERROR: unable to install the AMD DevCloud ROCm PATH profile!" >&2
        return 1
    fi
    _temp_path=""

    echo "Installed exact AMD DevCloud ROCm PATH profile block."
)

# Print the selected executable directory and the explicit library path for
#     command-scoped use without exporting runtime-selection variables.
# Usage: print_amd_devcloud_rocm_paths_dont_wrap
# Returns: 0 after printing the versioned paths; 1 for an unexpected argument
print_amd_devcloud_rocm_paths_dont_wrap() {
    if [ "$#" -ne 0 ]; then
        echo "ERROR: AMD DevCloud ROCm path reporting expects no arguments!" >&2
        return 1
    fi
    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would report versioned PATH, ROCM_HOME, and LD_LIBRARY_PATH use."
        return 0
    fi

    echo "ROCm home for command-scoped ROCM_HOME: ${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}"
    echo "ROCm executable directory: ${AMD_DEVCLOUD_ROCM_VERSIONED_BIN}"
    echo "ROCm library directory for command-scoped LD_LIBRARY_PATH: ${AMD_DEVCLOUD_ROCM_VERSIONED_LIBRARY_DIR}"
    printf "Current-shell PATH command: export PATH='%s':\"\${PATH}\"\n" \
        "${AMD_DEVCLOUD_ROCM_VERSIONED_BIN}"
    printf "Workload example: env ROCM_HOME='%s' LD_LIBRARY_PATH='%s' command [arguments...]\n" \
        "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}" \
        "${AMD_DEVCLOUD_ROCM_VERSIONED_LIBRARY_DIR}"
    echo "New login shells will select the versioned executable directory after profile setup."
    echo "Existing shells remain unchanged until the printed PATH command is run."
    echo "Rerun DevCloud setup to print these paths again; completed stages remain skipped."
    echo "Persistent ROCm runtime-selection variables are not configured."
}

# Verify the running-kernel DKMS installation and the adopted DevCloud GPU
#     identity after the driver-specific reboot.
# Usage: no arguments required
# Returns: 0 after exact DKMS, device, architecture, and driver-version
#          checks; 1 on failed observations or an unexpected environment
# shellcheck disable=SC2120 # Argument rejection is part of the helper contract.
verify_amd_devcloud_post_driver_state_dont_wrap() {
    local _required_command
    local _pci_output
    local _pci_line
    local _pci_count=0
    local _kernel_release
    local _machine_arch
    local _dkms_output
    local _expected_dkms_output
    local _amd_smi_json
    local _amd_smi_fields
    local _gpu_market_name
    local _gpu_arch
    local _driver_version
    local _extra_field

    if [ "$#" -ne 0 ]; then
        echo "ERROR: post-driver verification expects no arguments!" >&2
        return 1
    fi
    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Would verify the running-kernel AMDGPU DKMS state,"
        echo "[PLAN ONLY]     loaded driver and KFD device, single MI300X VF,"
        echo "[PLAN ONLY]     native ${AMD_DEVCLOUD_EXPECTED_GPU_ARCH} architecture, and AMD SMI"
        echo "[PLAN ONLY]     driver version ${AMD_DEVCLOUD_EXPECTED_AMD_SMI_DRIVER_VERSION}."
        return 0
    fi

    for _required_command in dkms jq lspci uname; do
        if ! command -v "${_required_command}" >/dev/null 2>&1; then
            echo "ERROR: post-driver verification requires '${_required_command}'!" >&2
            return 1
        fi
    done
    if ! _amd_devcloud_amd_smi_is_executable; then
        echo "ERROR: versioned AMD SMI command is not executable:" >&2
        echo "    ${AMD_DEVCLOUD_AMD_SMI_PATH}" >&2
        return 1
    fi
    if ! _amd_devcloud_amdgpu_module_is_loaded; then
        echo "ERROR: the amdgpu module is not loaded after the driver reboot!" >&2
        return 1
    fi
    if ! _amd_devcloud_kfd_is_present; then
        echo "ERROR: /dev/kfd is unavailable after the driver reboot!" >&2
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
    if [ "${_pci_count}" -ne 1 ]; then
        echo "ERROR: expected exactly one AMD DevCloud PCI device" >&2
        echo "    ${AMD_DEVCLOUD_EXPECTED_BARE_PCI_DEVICE_ID}; observed ${_pci_count}!" >&2
        return 1
    fi

    if ! _kernel_release="$(uname --kernel-release)" ||
        [ -z "${_kernel_release}" ]; then
        echo "ERROR: unable to determine the running kernel release!" >&2
        return 1
    fi
    if ! _machine_arch="$(uname --machine)" ||
        [ "${_machine_arch}" != "${AMD_DEVCLOUD_EXPECTED_DKMS_ARCH}" ]; then
        echo "ERROR: expected DKMS machine architecture" >&2
        echo "    '${AMD_DEVCLOUD_EXPECTED_DKMS_ARCH}', observed '${_machine_arch}'!" >&2
        return 1
    fi
    _expected_dkms_output="amdgpu/${AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION}, ${_kernel_release}, ${_machine_arch}: installed"
    if ! _dkms_output="$(LC_ALL=C dkms status \
        "amdgpu/${AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION}" \
        -k "${_kernel_release}/${_machine_arch}")"; then
        echo "ERROR: unable to inspect running-kernel AMDGPU DKMS state!" >&2
        return 1
    fi
    if [ "${_dkms_output}" != "${_expected_dkms_output}" ]; then
        echo "ERROR: running-kernel AMDGPU DKMS state is unexpected:" >&2
        printf '    %s\n' "${_dkms_output}" >&2
        return 1
    fi

    if ! _amd_smi_json="$(_amd_devcloud_run_amd_smi_static)"; then
        echo "ERROR: versioned AMD SMI failed to report GPU state!" >&2
        return 1
    fi
    if ! _amd_smi_fields="$(printf '%s\n' "${_amd_smi_json}" |
        jq --raw-output --exit-status \
            --argjson gpu_index "${AMD_DEVCLOUD_EXPECTED_GPU_INDEX}" '
                .gpu_data
                | select(type == "array")
                | map(select(.gpu == $gpu_index))
                | select(length == 1)
                | .[0]
                | [.asic.market_name,
                   .asic.target_graphics_version,
                   .driver.version]
                | select(all(.[]; type == "string" and length > 0))
                | @tsv')"; then
        echo "ERROR: AMD SMI did not report one complete selected-GPU record!" >&2
        return 1
    fi
    case ${_amd_smi_fields} in
        *$'\n'*)
            echo "ERROR: AMD SMI reported ambiguous selected-GPU records!" >&2
            return 1
            ;;
    esac
    IFS=$'\t' read -r _gpu_market_name _gpu_arch _driver_version \
        _extra_field <<< "${_amd_smi_fields}"
    if [ -n "${_extra_field}" ] ||
        [ "${_gpu_market_name}" != "${AMD_DEVCLOUD_EXPECTED_GPU_MARKET_NAME}" ]; then
        echo "ERROR: unexpected AMD SMI GPU identity '${_gpu_market_name}'!" >&2
        return 1
    fi
    if [ "${_gpu_arch}" != "${AMD_DEVCLOUD_EXPECTED_GPU_ARCH}" ]; then
        echo "ERROR: expected native architecture" >&2
        echo "    '${AMD_DEVCLOUD_EXPECTED_GPU_ARCH}', observed '${_gpu_arch}'!" >&2
        return 1
    fi
    if [ "${_driver_version}" != \
        "${AMD_DEVCLOUD_EXPECTED_AMD_SMI_DRIVER_VERSION}" ]; then
        echo "ERROR: expected AMD SMI driver version" >&2
        echo "    '${AMD_DEVCLOUD_EXPECTED_AMD_SMI_DRIVER_VERSION}', observed '${_driver_version}'!" >&2
        return 1
    fi

    echo "AMD DevCloud post-driver verification passed."
    echo "Running kernel: ${_kernel_release} (${_machine_arch})"
    echo "AMDGPU DKMS: ${AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION} (installed)"
    echo "GPU: ${_gpu_market_name} (${_gpu_arch})"
    echo "AMD SMI driver version: ${_driver_version}"
}

# Print an environment report for the separate DevCloud acceptance workflow.
#     This function is read-only and does not create a persistent artifact.
# Usage: print_amd_devcloud_environment_report <os_release_path> \
#            <baseline_virtualenv_dir> <common_apt_requirements_path> \
#            <versioned_rocm_root>
# Returns: 0 after every observation is collected and printed; 1 if the
#          environment is incomplete or any observation fails
print_amd_devcloud_environment_report() (
    local _os_release_path
    local _baseline_virtualenv_dir
    local _common_apt_requirements_path
    local _versioned_rocm_root
    local _timestamp
    local _os_release
    local _kernel
    local _driver_and_gpu
    local _rocm_packages
    local _hip_version
    local _system_python
    local _baseline_python
    local _baseline_apt_versions
    local _baseline_python_versions
    local _package_name
    local -a _baseline_apt_packages=(cmake)

    if [ "$#" -ne 4 ]; then
        echo "ERROR: DevCloud environment reporting expects four arguments!" >&2
        return 1
    fi
    _os_release_path="$1"
    _baseline_virtualenv_dir="$2"
    _common_apt_requirements_path="$3"
    _versioned_rocm_root="$4"
    if [ ! -r "${_os_release_path}" ] ||
        [ ! -r "${_common_apt_requirements_path}" ] ||
        [ ! -x "${_baseline_virtualenv_dir}/bin/python" ] ||
        [ ! -x "${_versioned_rocm_root}/bin/hipconfig" ]; then
        echo "ERROR: required DevCloud acceptance-probe input is unavailable!" >&2
        return 1
    fi

    while IFS= read -r _package_name || [ -n "${_package_name}" ]; do
        case ${_package_name} in
            ''|*[!A-Za-z0-9+.-]*)
                echo "ERROR: invalid common APT package name '${_package_name}'!" >&2
                return 1
                ;;
        esac
        _baseline_apt_packages+=("${_package_name}")
    done < "${_common_apt_requirements_path}"

    # shellcheck disable=SC2119 # The verifier deliberately accepts no arguments.
    if ! _timestamp="$(date --utc +'%Y-%m-%dT%H:%M:%SZ')" ||
        ! _os_release="$(cat -- "${_os_release_path}")" ||
        ! _kernel="$(uname --kernel-release --machine)" ||
        ! _driver_and_gpu="$(verify_amd_devcloud_post_driver_state_dont_wrap)" ||
        ! _rocm_packages="$(dpkg-query --show \
            --showformat='${binary:Package}\t${Version}\n' \
            amdgpu-install "${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE}" \
            "${AMD_DEVCLOUD_AMD_SMI_PACKAGE}" \
            "${AMD_DEVCLOUD_ROCM_CORE_PACKAGE}" \
            "${AMD_DEVCLOUD_ROCM_METAPACKAGE}")" ||
        ! _hip_version="$(env \
            LD_LIBRARY_PATH="${_versioned_rocm_root}/lib" \
            "${_versioned_rocm_root}/bin/hipconfig" --version)" ||
        ! _system_python="$(python3 --version 2>&1)" ||
        ! _baseline_python="$("${_baseline_virtualenv_dir}/bin/python" \
            --version 2>&1)" ||
        ! _baseline_apt_versions="$(dpkg-query --show \
            --showformat='${binary:Package}\t${Version}\n' \
            "${_baseline_apt_packages[@]}")" ||
        ! _baseline_python_versions="$("${_baseline_virtualenv_dir}/bin/python" \
            -m pip freeze --all)"; then
        echo "ERROR: unable to collect the complete DevCloud environment report!" >&2
        return 1
    fi

    printf 'Observed UTC: %s\n\n' "${_timestamp}" || return 1
    printf '[OS]\n%s\n\n' "${_os_release}" || return 1
    printf '[Kernel]\n%s\n\n' "${_kernel}" || return 1
    printf '[AMDGPU and GPU]\n%s\n\n' "${_driver_and_gpu}" || return 1
    printf '[ROCm packages]\n%s\n' "${_rocm_packages}" || return 1
    printf 'hipconfig --version: %s\n\n' "${_hip_version}" || return 1
    printf '[Python]\nSystem: %s\nBaseline: %s\n\n' \
        "${_system_python}" "${_baseline_python}" || return 1
    printf '[Baseline APT packages]\n%s\n\n' \
        "${_baseline_apt_versions}" || return 1
    printf '[Baseline Python packages]\n%s\n' \
        "${_baseline_python_versions}" || return 1
)
