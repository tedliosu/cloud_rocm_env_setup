
# Helper function to run a stage
# Usage: run_stage <milestones_directory_path> <function_to_run> [function_arguments]...
run_stage() {

    _milestones_dir="$1"
    shift
    _func_to_run="$1"
    shift
    _done_marker_file="${_milestones_dir}/${_func_to_run}.done"

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
        echo "--- skipping stage: ${_func_to_run} (already complete) ---"
    fi

}

# Assert basic environment stats helper, assuming Ubuntu-like distro
# Usage: ensure_basic_env_sanity_dont_wrap <expected_distro_name> <expected_distro_ver> \
#                                          <expected_rocm_ver> <expected_rocm_ver_regex>
ensure_basic_env_sanity_dont_wrap() {

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
    ROCM_DETECTED_VER="$(hipconfig --rocmpath | cut -d"-" -f2)"
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
    sudo --set-home apt-get install --assume-yes ca-certificates gpg wget
    test -f "${_kitware_test_file}" ||
        wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null |
            gpg --dearmor - | sudo --set-home tee "${_kitware_signing_file}" >/dev/null
    echo "deb ${_signed_by_str} https://apt.kitware.com/ubuntu/ $1 main" |
        sudo --set-home tee /etc/apt/sources.list.d/kitware.list >/dev/null
    sudo --set-home apt-get update
    test -f "${_kitware_test_file}" || sudo --set-home rm "${_kitware_signing_file}"
    sudo --set-home apt-get install --assume-yes --reinstall kitware-archive-keyring
    sudo --set-home apt-get install --assume-yes cmake
   
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

# Install base deep learning projects' required packages into a virtualenv
# Usage: ensure_base_dl_virtualenv <deep_learning_virtenv_dirpath> <rocm_ver_string> \
#            <torch_specific_requirements_txt_path> <non_torch_requirements_txt_path> \
#            <torchcodec_ver_str>
ensure_base_dl_virtualenv() {

    test -d "$1" && rm --recursive --force "$1"
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

    test -d "$1" && rm --recursive --force "$1"
    virtualenv "$1"
    # Parameterized source since this function encapsulate setup logic invariants
    # shellcheck disable=SC1090,SC1091
    . "$1/bin/activate"
    pip install --upgrade pip
    pip install --requirement "$3"
    test -d "$2" && rm --recursive --force "$2"
    git clone https://github.com/cupy/cupy.git "$2"
    git -C "$2" fetch origin pull/9748/head:pr-9748-hipmask
    git -C "$2" checkout pr-9748-hipmask
    git -C "$2" config --global user.email "placeholder@example.com"
    git -C "$2" config --global user.name "placeholder"
    git -C "$2" merge 9263620693c892864c52d2703b862dcf1c264c6a --no-edit
    git -C "$2" submodule update --init --recursive
    ROCM_HOME="$(hipconfig --rocmpath | cut -d"-" -f1)" || {
        echo "FAILED to detect 'ROCM_HOME'!" >&2
        exit 1
    }
    HCC_AMDGPU_TARGET="$(rocm-smi --device 0 --showproductname --json 2>/dev/null | \
                             jq --raw-output '.card0."GFX Version"' | tr --delete "\n")" || {
        echo "FAILED to detect GFX Version of ROCm device 0!" >&2
        exit 1
    }
    CUPY_NUM_BUILD_JOBS="$(nproc)"
    echo "GOT: ROCM_HOME=${ROCM_HOME}, HCC_AMDGPU_TARGET=${HCC_AMDGPU_TARGET}," \
        "CUPY_NUM_BUILD_JOBS=${CUPY_NUM_BUILD_JOBS}"
    export ROCM_HOME
    export HCC_AMDGPU_TARGET
    export CUPY_NUM_BUILD_JOBS
    export CUPY_INSTALL_USE_HIP=1
    pip wheel --wheel-dir "$2/dist" "$2"
    pip install "$2/dist"/cupy*.whl
    _last_pip_status="$?"
    if [ "${_last_pip_status}" -eq 0 ]; then
        rm --recursive --force "$2"
    fi
    deactivate

}

# Install ComfyUI's required packages into a virtualenv
# Usage: ensure_comfyui_virtualenv <deep_learning_virtenv_dirpath> <comfyui_clone_dir_path> \
#            <comfyui_version_tag> <torch_specific_requirements_txt_path> <non_torch_requirements_txt_path> \
#            <before_comfyui_install_pip_freeze_path> <after_comfyui_install_pip_freeze_path>
ensure_comfyui_virtualenv() {

    test -d "$2" && rm --recursive --force "$2"
    git clone https://github.com/Comfy-Org/ComfyUI.git "$2"
    git -C "$2" checkout "$3"
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
