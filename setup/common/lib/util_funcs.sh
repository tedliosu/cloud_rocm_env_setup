
# Source global helpers used in this script;
#    note that this sourcing assumes that the
#    main runner script will reside in directory
#    '../../*/bin' relative to this script!
. "../../../lib/comm_util_funcs.sh"

# Helper function to run a stage
# Usage: run_stage <milestones_directory_path> <function_to_run> [function_arguments]...
run_stage() {

    _milestones_dir="$1"
    shift
    _func_to_run="$1"
    shift
    _done_marker_file="${_milestones_dir}/${_func_to_run}.done"
    _skip_stage_msg="--- skipping stage: ${_func_to_run} (already complete) ---"

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        if [ ! -f "${_done_marker_file}" ]; then
            echo "[PLAN ONLY] ${_skip_stage_msg}"
        else
            echo "[PLAN ONLY] --- run stage ${_func_to_run} ---"
        fi
        return 0
    fi

    if [ ! -f "${_done_marker_file}" ]; then
        echo "--- starting stage: ${_func_to_run} ---"
        # ANY failure in the `&&` chain should trigger the bailout
        # shellcheck disable=SC2015
        "${_func_to_run}" "$@" && touch "${_done_marker_file}" && \
        echo "--- completed stage: ${_func_to_run} ---" || {
            echo "--- FAILED stage: ${_func_to_run} ---" >&2
            exit 1
        }
    else
        echo "${_skip_stage_msg}"
    fi

}

# Add user echo'ed by 'logname' to 'video' and 'render' groups if the
#     user is not in those groups already, and then reboot the system
#     for changes to take effect; rebooting is not strictly required
#     but we can't always assume login shell
# Usage: no arguments required
ensure_groups_maybe_reboot_dont_wrap() {

    _groups_changed=0
    _env_username="$(logname)" || {
        echo "FAILED to get 'LOGNAME'!" >&2
        exit 1
    }

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Ensure that user '${_env_username}' is" \
             "in 'video' and 'render' groups."
        echo "[PLAN ONLY] Then, reboot if group membership(s) changed."
        return 0
    fi

    echo "Ensuring that user '${_env_username}' is" \
         "in 'video' and 'render' groups..."

    if id --name --groups "${_env_username}" | \
        grep --quiet --word-regexp --invert-match "video"; then
        echo "'${_env_username}' NOT in video group, adding..."
        sudo --set-home usermod --append --groups video "${_env_username}"
        _groups_changed=1
    fi

    if id --name --groups "${_env_username}" | \
        grep --quiet --word-regexp --invert-match "render"; then
        echo "'${_env_username}' NOT in render group, adding..."
        sudo --set-home usermod --append --groups render "${_env_username}"
        _groups_changed=1
    fi

    if [ "${_groups_changed}" -eq 0 ]; then
        echo "User already belongs to render and video groups."
    else
        echo "User group membership(s) changed, rebooting..."
        sudo --set-home reboot
        exit 0
    fi

}

# Assert basic environment stats helper, assuming Ubuntu-like distro
# Usage: ensure_basic_env_sanity_dont_wrap <expected_distro_name> <expected_distro_ver> \
#                                          <expected_rocm_ver> <expected_rocm_ver_regex>
ensure_basic_env_sanity_dont_wrap() {

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Ensure that current environment is $1 $2 distro,"
        echo "[PLAN ONLY] ensure that amdgpu dkms is loaded according to 'rocminfo',"
        echo "[PLAN ONLY] and ensure that 'hipconfig' reports ROCm version ~$3."
        return 0
    fi

    if ! grep --quiet "DISTRIB_ID=$1" /etc/lsb-release ||
       ! grep --quiet "DISTRIB_RELEASE=$2" /etc/lsb-release; then
        echo "Got unexpected '/etc/lsb-release' with contents:" >&2
        echo >&2
        cat /etc/lsb-release >&2
        echo >&2
        echo  "    This IS NOT $1 $2; bailing!" >&2
        exit 1
    fi
    if rocminfo | grep --ignore-case --quiet "NOT loaded"; then
        echo "amdgpu dkms not detected; bailing!" >&2
        exit 1
    fi
    ROCM_DETECTED_VER="$(hipconfig --rocmpath | cut --delimiter="-" --fields=2)"
    if echo "$ROCM_DETECTED_VER" | \
       grep --extended-regexp --invert-match --quiet "$4"; then
        echo "'hipconfig' reports ROCm userland version $ROCM_DETECTED_VER!" >&2
        echo >&2
        echo "    Please update all environment setup logic and configs" >&2
        echo >&2
        echo "    before rerunning this script, as assumed version is" >&2
        echo " ~$3!" >&2
        exit 1
    fi

}

# Check web hosted file availability using wget with http(s)
# Usage: check_wget_fetch_dont_wrap <web_url_to_file>
# Returns: 0 on success of web hosted file fetch; 1 otherwise
check_wget_fetch_dont_wrap() {

    if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        echo "[PLAN ONLY] Ensure that '$1' is reachable,"
        echo "[PLAN ONLY] via test download using 'wget'; 'wget' is installed using"
        echo "[PLAN ONLY] apt-get before test download if it isn't available."
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
            echo "[PLAN ONLY] Report that PPA(s) in '$1'"
            echo "[PLAN ONLY] are already disabled."
        else
            echo "[PLAN ONLY] Attempt to disable PPA(s) in '$1'"
            echo "[PLAN ONLY] via 'mv' command."
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

# System update (no kernel update by default)
# Usage: no arguments required
apt_get_sys_update() {
    sudo --set-home apt-get update
    sudo --set-home env NEEDRESTART_MODE="a" apt-get upgrade --assume-yes
}

# Reboot once helper (for after a system update)
# Usage: reboot_once_dont_wrap <milestones_directory>
reboot_once_dont_wrap() {
    reboot_marker_file="$1/reboot_once_dont_wrap.done"
    _reboot_skip_msg="--- skipping stage: reboot_once_dont_wrap (already complete) ---"
   if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
        if [ ! -f "${reboot_marker_file}" ]; then
            echo "[PLAN ONLY] Record reboot request and reboot system"
        else
            echo "[PLAN ONLY] ${_reboot_skip_msg}"
        fi
        return 0
    fi
    if [ ! -f "$reboot_marker_file" ]; then
        echo "Reboot required, performing ONE reboot..."
        touch "$reboot_marker_file"
        sudo --set-home reboot
        exit 0
    else
        echo "${_reboot_skip_msg}"
    fi
}

# up-to-date CMake setup, assuming Ubuntu
# Usage: ensure_latest_cmake <ubuntu_distro_codename>
ensure_latest_cmake() {

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
    sudo --set-home apt-get install --assume-yes cmake
   
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
    _w3m_hidden_dir="$1/.w3m"
    mkdir --parent "${_w3m_hidden_dir}"
    touch "${_w3m_hidden_dir}/history"
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
    which fastfetch >/dev/null 2>&1 && rm --recursive "$4"

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
#            <non_cupy_requirements_txt_path>
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
    git clone --branch=v14 https://github.com/cupy/cupy.git "$2"
    git -C "$2" submodule update --init --recursive
    ROCM_HOME="$(hipconfig --rocmpath | cut --delimiter="-" --fields=1)" || {
        echo "FAILED to detect 'ROCM_HOME'!" >&2
        exit 1
    }
    HCC_AMDGPU_TARGET="$(rocm-smi --device 0 --showproductname --json 2>/dev/null | \
                             jq --raw-output '.card0."GFX Version"' | tr --delete "\n")" || {
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
        elif echo "${HCC_AMDGPU_TARGET}" | grep --quiet "^gfx110[12]$"; then
            echo "Building for '${_gfx11_fallback_arch}' as fallback arch requested," \
                                                                    "and 'native' arch"
            echo "    is supported RDNA 3 non-'${_gfx11_fallback_arch}' arch; " \
                                               "appending '${_gfx11_fallback_arch}' to"
            echo "    'HCC_AMDGPU_TARGET'..."
            HCC_AMDGPU_TARGET="${HCC_AMDGPU_TARGET},${_gfx11_fallback_arch}"
        else
            echo "WARNING: Building for '${_gfx11_fallback_arch}' as fallback arch" >&2
            echo "    requested, but 'native' arch of '${HCC_AMDGPU_TARGET}' is NOT" >&2
            echo "    compatible with such a request! NOT proceeding to modify" >&2
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
    pip wheel --wheel-dir "$2/dist" "$2"
    pip install "$2/dist"/cupy*.whl
    _last_pip_status="$?"
    if [ "${_last_pip_status}" -eq 0 ]; then
        guarded_rm_rf "$2"
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
