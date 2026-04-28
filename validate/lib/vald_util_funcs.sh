
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

# Usage
#
validate_basic_hipco() {

    echo "NOT IMPLEMENTED"

}
