# shellcheck shell=bash

# Utility shell functions each used to encapsulate non-trivial amounts of logic
#     needed for basic validation of specific ROCm workloads

# Source global helpers used in this script;
#    note that this sourcing assumes that the
#    main runner script will reside in directory
#    '../bin' relative to this script!
. "../../lib/comm_util_funcs.sh"

_FALSE_NUM_VAL=0

# Check that a value is one ordinary filename rather than a path or list.
# Usage: is_plain_filename <filename>
# Returns: 0 for one nonempty filename component; 1 otherwise
is_plain_filename() {

    [ "$#" -eq 1 ] || return 1
    case ${1} in
        ''|.|..|*/*|*$'\n'*) return 1;;
        *) return 0;;
    esac

}

# Validate and canonicalize one ROCm root reported by the caller.
# Usage: canonicalize_rocm_validation_root <reported_rocm_root>
# Returns: 0 and prints the canonical root; 1 for an invalid or incomplete root
canonicalize_rocm_validation_root() {

    local _reported_rocm_root
    local _canonical_rocm_root
    local _rocm_library_dir

    if [ "$#" -ne 1 ]; then
        echo "ERROR: ROCm root canonicalization expects one reported root!" >&2
        return 1
    fi
    _reported_rocm_root="$1"
    case ${_reported_rocm_root} in
        ''|*$'\n'*)
            echo "ERROR: hipconfig reported an empty or multiline ROCm root!" >&2
            return 1
            ;;
        /*) ;;
        *)
            echo "ERROR: hipconfig reported a non-absolute ROCm root:" >&2
            echo "    ${_reported_rocm_root}" >&2
            return 1
            ;;
    esac
    if ! _canonical_rocm_root="$(realpath --canonicalize-existing -- \
        "${_reported_rocm_root}")" || [ ! -d "${_canonical_rocm_root}" ]; then
        echo "ERROR: unable to resolve hipconfig ROCm root:" >&2
        echo "    ${_reported_rocm_root}" >&2
        return 1
    fi
    _rocm_library_dir="${_canonical_rocm_root}/lib"
    if [ ! -d "${_rocm_library_dir}" ]; then
        echo "ERROR: selected ROCm root has no lib directory:" >&2
        echo "    ${_canonical_rocm_root}" >&2
        return 1
    fi

    printf '%s\n' "${_canonical_rocm_root}"

}

# Validate environment UFW configuration status
# Usage: validate_ufw_config <strict_mode_flag>
# Returns: with strict checking, 0 only for the known UFW baseline; with relaxed
#     checking, 0 after reporting any UFW classification
validate_ufw_config() (

    # Keep command output used for exact UFW comparisons stable without changing
    #     the locale of unrelated validation stages.
    LC_ALL=C
    export LC_ALL

    if ! _collected_ufw_status=$(sudo --set-home ufw status 2>/dev/null) ||
        ! _collected_ufw_added=$(sudo --set-home ufw show added 2>/dev/null) ||
        ! _collected_ufw_defaults=$(sudo --set-home \
            grep --extended-regexp \
                "${UFW_DEFAULTS_SELECTOR_REGEX}" \
                /etc/default/ufw 2>/dev/null); then
        if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
            echo "ERROR: UFW classification is ${UFW_UNK_STATE}; unable to collect current UFW state!" >&2
        else
            echo "WARN: UFW classification is ${UFW_UNK_STATE}; relaxed checking is enabled!" >&2
        fi
        echo "   Please check output of each of following commands manually:" >&2
        echo "     1. sudo -H ufw status" >&2
        echo "     2. sudo -H ufw show added" >&2
        printf "     3. sudo -H grep -E '%s' /etc/default/ufw\n" \
            "${UFW_DEFAULTS_SELECTOR_REGEX}" >&2
        if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
            return 1
        fi
        return 0
    fi
    _ufw_classification=$(classify_ufw_state "${_collected_ufw_status}" \
        "${_collected_ufw_added}" "${_collected_ufw_defaults}")

    case ${_ufw_classification} in
        "${UFW_KNOWN_BASELINE}")
            echo "PASSED: UFW classification is ${_ufw_classification}!"
            return 0
            ;;
        "${UFW_INSTALLED_FRESH}")
            if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
                echo "ERROR: UFW classification is ${_ufw_classification}; strict checking requires ${UFW_KNOWN_BASELINE}!" >&2
            else
                echo "WARN: UFW classification is ${_ufw_classification}; relaxed checking is enabled!" >&2
            fi
            print_ufw_diagnostics "${_collected_ufw_status}" \
                "${_collected_ufw_added}" \
                "${_collected_ufw_defaults}"
            if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
                return 1
            fi
            return 0
            ;;
        "${UFW_CUSTOM_STATE}")
            if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
                echo "ERROR: UFW classification is ${_ufw_classification}; strict checking requires ${UFW_KNOWN_BASELINE}!" >&2
            else
                echo "WARN: UFW classification is ${_ufw_classification}; relaxed checking is enabled!" >&2
            fi
            print_ufw_diagnostics "${_collected_ufw_status}" \
                "${_collected_ufw_added}" \
                "${_collected_ufw_defaults}"
            if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
                return 1
            fi
            return 0
            ;;
        "${UFW_UNK_STATE}")
            if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
                echo "ERROR: UFW classification is ${_ufw_classification}; strict checking requires ${UFW_KNOWN_BASELINE}!" >&2
            else
                echo "WARN: UFW classification is ${_ufw_classification}; relaxed checking is enabled!" >&2
            fi
            print_ufw_diagnostics "${_collected_ufw_status}" \
                "${_collected_ufw_added}" \
                "${_collected_ufw_defaults}"
            if [ "${1}" -ne "${_FALSE_NUM_VAL}" ]; then
                return 1
            fi
            return 0
            ;;
        *)
            echo "ERROR: internal UFW classification failure!" >&2
            return 1
            ;;
    esac

)

# Validate the complete source-built CuPy shared workload environment gate.
# Usage: validate_source_built_cupy_env <virtualenv_dirpath> \
#            <activation_script_relpath> <validation_lib_dirpath> \
#            <numba_library_paths> <strict_presence_flag> \
#            <strict_presence_cli_flag>
# Returns: 0 after all required checks pass or optional absence is reported;
#     1 for required absence or failure of either required validation
validate_source_built_cupy_env() (

    _source_built_cupy_env_dirpath="${1}"
    _activation_script_relpath="${2}"
    _validation_lib_dirpath="${3}"
    _numba_library_paths="${4}"
    _strict_presence_flag="${5}"
    _strict_presence_cli_flag="${6}"

    if [ ! -f "${_source_built_cupy_env_dirpath}/${_activation_script_relpath}" ]; then
        if [ "${_strict_presence_flag}" -ne "${_FALSE_NUM_VAL}" ]; then
            echo "FAILED to detect source-built CuPy environment," >&2
            echo "(${_strict_presence_cli_flag} flag detected)!" >&2
            return 1
        fi
        echo "Source-built CuPy environment and ${_strict_presence_cli_flag}" \
            "flag both not detected,"
        echo "skipping associated validations..."
        return 0
    fi

    # Intentional variable path sourcing; the subshell keeps activation local
    #     to this complete environment gate.
    # shellcheck disable=SC1090,SC1091
    . "${_source_built_cupy_env_dirpath}/${_activation_script_relpath}"
    if ! env CUPY_ACCELERATORS="cub" python3 \
        "${_validation_lib_dirpath}/cupy_numpy_smoke.py"; then
        echo "FAILED source-built CuPy custom-kernel validation!" >&2
        return 1
    fi
    if ! env LD_LIBRARY_PATH="${_numba_library_paths}" python3 \
        "${_validation_lib_dirpath}/numba_smoke.py"; then
        echo "FAILED source-built environment Numba/TBB validation!" >&2
        return 1
    fi
    echo "NOTE: Numba test used LD_LIBRARY_PATH='${_numba_library_paths}'"
    echo "PASSED complete source-built CuPy environment validation gate!"

)

# Validate the complete packaged AMD RAPIDS shared workload environment gate.
# Usage: validate_packaged_amd_rapids_env <virtualenv_dirpath> \
#            <activation_script_relpath> <validation_lib_dirpath> \
#            <canonical_rocm_home> <numba_library_paths> <strict_presence_flag> \
#            <strict_presence_cli_flag> <max_canny_disagreement_percent>
# Returns: 0 after all required checks pass or optional absence is reported;
#     1 for required absence or failure of any required validation
validate_packaged_amd_rapids_env() (
    _packaged_amd_rapids_env_dirpath="${1}"
    _activation_script_relpath="${2}"
    _validation_lib_dirpath="${3}"
    _canonical_rocm_home="${4}"
    _numba_library_paths="${5}"
    _strict_presence_flag="${6}"
    _strict_presence_cli_flag="${7}"
    _max_canny_disagreement_percent="${8}"

    if [ ! -f "${_packaged_amd_rapids_env_dirpath}/${_activation_script_relpath}" ]; then
        if [ "${_strict_presence_flag}" -ne "${_FALSE_NUM_VAL}" ]; then
            echo "FAILED to detect packaged AMD RAPIDS environment," >&2
            echo "(${_strict_presence_cli_flag} flag detected)!" >&2
            return 1
        fi
        echo "Packaged AMD RAPIDS environment and ${_strict_presence_cli_flag}" \
            "flag both not detected,"
        echo "skipping associated validations..."
        return 0
    fi

    # Intentional variable path sourcing; the subshell keeps activation local
    #     to this complete environment gate.
    # shellcheck disable=SC1090,SC1091
    . "${_packaged_amd_rapids_env_dirpath}/${_activation_script_relpath}"
    if ! env CUPY_ACCELERATORS="cub" python3 \
        "${_validation_lib_dirpath}/cupy_numpy_smoke.py"; then
        echo "FAILED packaged AMD CuPy custom-kernel validation!" >&2
        return 1
    fi
    if ! env LD_LIBRARY_PATH="${_numba_library_paths}" python3 \
        "${_validation_lib_dirpath}/numba_smoke.py"; then
        echo "FAILED packaged AMD RAPIDS Numba/TBB validation!" >&2
        return 1
    fi
    echo "NOTE: Numba test used LD_LIBRARY_PATH='${_numba_library_paths}'"
    if ! env CUPY_ACCELERATORS="cub" ROCM_HOME="${_canonical_rocm_home}" \
        python3 "${_validation_lib_dirpath}/hipcim_canny_smoke.py" \
            --max-disagreement-percent "${_max_canny_disagreement_percent}"; then
        echo "FAILED packaged cuCIM Canny correctness validation!" >&2
        return 1
    fi
    echo "PASSED complete packaged AMD RAPIDS environment validation gate!"
)

# Validate Triton JIT works and resulting kernel runs using upstream Triton fp16 GEMM
#     tutorial code
# Usage: validate_basic_triton <cloned_triton_repo_dirpath> <cloned_triton_repo_branch_id> \
#                              <gemm_tutorial_patch_path>
validate_basic_triton() {

    _tutorials_dirpath="python/tutorials"
    _test_common_str_triton="Triton fp16 matmul tutorial based smoke test!"
    test -d "$1" && guarded_rm_rf "$1"
    git -c advice.detachedHead=false clone \
              --filter=blob:none --sparse --branch "$2" \
              https://github.com/triton-lang/triton.git "$1"
    git -C "$1" -c advice.detachedHead=false \
                 sparse-checkout set "${_tutorials_dirpath}"
    git -C "$1" apply "$3"
    if python3 "$1/${_tutorials_dirpath}/03-matrix-multiplication.py"; then
        guarded_rm_rf "$1"
        echo "PASSED ${_test_common_str_triton}"
    else
        echo "FAILED ${_test_common_str_triton}" >&2
        exit 1
    fi

}

# Validate hipCollections static map host bulk API example works
#     with system ROCm and CMake.
# Usage: validate_basic_hipco <cloned_hipco_repo_abs_dirpath> <hipco_target_commit_sha> \
#                             <gfx_target_arch(s)> <cmakelists_patch_path> \
#                             <cloned_rocm_ds_cmake_repo_abs_dirpath> <rocm_ds_cmake_target_commit_sha> \
#                             <version_json_patch_path> <canonical_rocm_home>
validate_basic_hipco() {

    local _rocm_home="${8}"

    _build_dir_name="build"
    _lib_cmake_relpath="lib/cmake"
    _rapids_cmake_relpath="rapids-cmake"
    _example_bin_name="STATIC_MAP_HOST_BULK_EXAMPLE"
    _test_common_str="'${_example_bin_name}' hipCollections smoke test!"
    test -d "$1" && guarded_rm_rf "$1"
    git clone https://github.com/ROCm/hipCollections.git "$1"
    git -C "$1" -c advice.detachedHead=false checkout "$2"
    git -C "$1" submodule update --init --recursive
    test -d "$5" && guarded_rm_rf "$5"
    git clone https://github.com/ROCm-DS/ROCmDS-cmake.git "$5"
    git -C "$5" -c advice.detachedHead=false checkout "$6"
    git -C "$5" submodule update --init --recursive
    git -C "$5" apply "$7"
    if [ -z "${_rocm_home}" ]; then
        echo "FAILED: canonical ROCm home was not supplied!" >&2
        exit 1
    fi
    # IMPORTANT - env var could be unset, so we use default empty!
    if echo "$3" | grep --quiet "gfx110[01]"; then
        git -C "$1" apply "$4"
        env CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-}:${_rocm_home}/${_lib_cmake_relpath}" \
                                 RAPIDS_CMAKE_MODULE_PATH="$5/${_rapids_cmake_relpath}" cmake \
                                 -Drapids-cmake-dir="$5/${_rapids_cmake_relpath}" -DUSE_WARPSIZE_32=1 \
                                 -DCMAKE_HIP_ARCHITECTURES="$3" -DBUILD_TESTS=OFF -DBUILD_BENCHMARKS=OFF \
                                 -S "$1" -B "$1/${_build_dir_name}"
    else
        env CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-}:${_rocm_home}/${_lib_cmake_relpath}" \
                                 RAPIDS_CMAKE_MODULE_PATH="$5/${_rapids_cmake_relpath}" cmake \
                                 -Drapids-cmake-dir="$5/${_rapids_cmake_relpath}" \
                                 -DCMAKE_HIP_ARCHITECTURES="$3" -DBUILD_TESTS=OFF -DBUILD_BENCHMARKS=OFF \
                                 -S "$1" -B "$1/${_build_dir_name}"
    fi
    cmake --build "$1/${_build_dir_name}" --target "${_example_bin_name}"
    if "$1/${_build_dir_name}/examples/${_example_bin_name}" | \
        grep --ignore-case "success"; then
        echo "PASSED ${_test_common_str}"
    else
        echo "FAILED ${_test_common_str}" >&2
        exit 1
    fi
    guarded_rm_rf "$1" "$5"

}
