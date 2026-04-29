
# Utility shell functions each used to encapsulate non-trivial amounts of logic
#     needed for basic validation of specific ROCm workloads

# Validate Triton JIT works and resulting kernel runs using upstream Triton fp16 GEMM
#     tutorial code
# Usage: validate_basic_triton <cloned_triton_repo_dirpath> <cloned_triton_repo_branch_id> \
#                              <gemm_tutorial_patch_path>
validate_basic_triton() {

    _tutorials_dirpath="python/tutorials"
    test -d "$1" && rm --recursive --force "$1"
    git clone --filter=blob:none --sparse --branch "$2" \
              https://github.com/triton-lang/triton.git "$1"
    git -C "$1" sparse-checkout set "${_tutorials_dirpath}"
    git -C "$1" apply "$3"
    python3 "$1/${_tutorials_dirpath}/03-matrix-multiplication.py"
    _py_last_status="$?"
    if [ "${_py_last_status}" -eq 0 ]; then
        rm --recursive --force "$1"
    fi

}

# Validate hipCollections static map host bulk API example works
#     with system ROCm and CMake. (Planned: allow for validation with RDNA 3 systems)
# Usage: validate_basic_hipco <cloned_hipco_repo_abs_dirpath> <hipco_target_commit_sha> \
#                             <gfx_target_arch(s)>
validate_basic_hipco() {

    _build_dir_name="build"
    _example_bin_name="STATIC_MAP_HOST_BULK_EXAMPLE"
    _test_common_str="'${_example_bin_name}' hipCollections smoke test!"
    test -d "$1" && rm --recursive --force "$1"
    git clone https://github.com/ROCm/hipCollections.git "$1"
    git -C "$1" checkout "$2"
    git -C "$1" submodule update --init --recursive
    ROCM_HOME_DIR="$(hipconfig --rocmpath | cut -d"-" -f1)" || {
        echo "FAILED to detect 'ROCM_HOME_DIR'!" >&2
        exit 1
    }
    env CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH}:${ROCM_HOME_DIR}/lib/cmake" \
        cmake -DCMAKE_HIP_ARCHITECTURES="$3" -S "$1" -B "$1/${_build_dir_name}"
    cmake --build "$1/${_build_dir_name}" --target "${_example_bin_name}"
    if "$1/${_build_dir_name}/examples/${_example_bin_name}" | \
        grep --ignore-case --invert-match "success"; then
        echo "FAILED ${_test_common_str}" >&2
        exit 1
    else
        echo "PASSED ${_test_common_str}"
    fi
    rm --recursive --force "$1"

}
