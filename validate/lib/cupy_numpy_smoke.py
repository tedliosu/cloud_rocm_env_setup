# pylint: disable=c-extension-no-member
"""
Smoke test to catch obvious ABI-mismatch and ROCm/CUDA GPU
    (CUB) detection issues with cupy <-> numpy, along with
    Canny-critical CuPy custom-kernel compatibility issues
"""
import sys
from os import environ
import warnings
import numpy as npy
import cupy as cpy

_MAT_A_ROWS: int = 256
_MAT_A_COLS: int = 784
_MAT_B_COLS: int = 512
_MAT_D_SIZE: int = 600
_ARR_LEN: int = 1000000 # To trigger CUB dispatch
_MASK_RAW_VAL_LIM: int = 8192
_ATOMIC_CAS_ATTEMPTS_PER_SLOT: int = 4
_ATOMIC_CAS_BLOCK_SIZE: int = 128
_ATOMIC_CAS_SCALE_SLOT_COUNT: int = 250000

_ATOMIC_CAS_TYPE_COMPAT_KERN = cpy.ElementwiseKernel(
    'raw T comparison_values, raw T replacement_values, int32 attempts_per_slot',
    'raw T slot_values, raw T returned_old_values',
    '''
#if defined(__HIPCC_RTC__)
        // ROCm 7.2 HIPRTC exposes runtime-compilation type traits through
        // __hip_internal. This dependency is intentionally version-sensitive.
        using atomic_t = typename __hip_internal::conditional<
            __hip_internal::is_same<T, long long>::value,
            unsigned long long,
            T
        >::type;
#elif defined(__CUDACC_RTC__)
        using atomic_t = typename cuda::std::conditional<
            cuda::std::is_same<T, long long>::value,
            unsigned long long,
            T
        >::type;
#else
#error Unsupported runtime-compilation backend
#endif

        int slot_idx = i / attempts_per_slot;
        atomic_t old_value = atomicCAS(
            (atomic_t*)&slot_values[slot_idx],
            atomic_t(comparison_values[slot_idx]),
            atomic_t(replacement_values[slot_idx])
        );
        returned_old_values[i] = T(old_value);
    ''',
    'atomic_cas_type_compat_kern',
    preamble='''
#if defined(__CUDACC_RTC__) && !defined(__HIPCC_RTC__)
#include <cuda/std/type_traits>
#endif
    '''
)

if __name__ == "__main__":

    curr_dev_ord = cpy.cuda.runtime.getDevice()
    dev_name = cpy.cuda.runtime.getDeviceProperties(curr_dev_ord)["name"].decode("utf-8")
    # pylint: disable=invalid-name
    python_ver_str = sys.version.replace("\n", " ")
    print("=== Relevant Environment Info of Versions ===")
    print(f"python: {python_ver_str}")
    print(f"numpy: {npy.__version__}")
    print(f"cupy: {cpy.__version__}")
    print(f"cupy cuda: {cpy.cuda.runtime.runtimeGetVersion()}")
    print(f"cupy driver: {cpy.cuda.runtime.driverGetVersion()}")
    print(f"Current device: {dev_name}")

    accel_backend = environ.get("CUPY_ACCELERATORS", "[None]")
    if accel_backend != "cub":
        warnings.warn("'cub' acceleration not requested! " + \
                      "Falling back to slow path for CuPy...",
                                       category=RuntimeWarning)

    for atomic_dtype in (npy.int32, npy.int64, npy.uint64):
        for atomic_case_name, atomic_slot_count in (
                ("tiny", 3), ("scale", _ATOMIC_CAS_SCALE_SLOT_COUNT)):
            atomic_dtype_obj = npy.dtype(atomic_dtype)
            atomic_base_value = (1 << 63) + 1024 \
                if atomic_dtype_obj == npy.dtype(npy.uint64) else 1024
            atomic_slot_offsets_cpu = npy.arange(atomic_slot_count,
                                                  dtype=atomic_dtype_obj)
            atomic_initial_values_cpu = atomic_slot_offsets_cpu + \
                npy.array(atomic_base_value, dtype=atomic_dtype_obj)
            atomic_comparison_values_cpu = atomic_initial_values_cpu.copy()
            atomic_comparison_values_cpu[1::3] += \
                npy.array(1, dtype=atomic_dtype_obj)
            atomic_replacement_values_cpu = atomic_initial_values_cpu + \
                npy.array(atomic_slot_count + 1, dtype=atomic_dtype_obj)
            atomic_matching_slots_cpu = \
                atomic_initial_values_cpu == atomic_comparison_values_cpu
            atomic_final_values_ref_cpu = npy.where(
                atomic_matching_slots_cpu,
                atomic_replacement_values_cpu,
                atomic_initial_values_cpu
            )
            atomic_initial_return_counts_ref_cpu = npy.where(
                atomic_matching_slots_cpu, 1, _ATOMIC_CAS_ATTEMPTS_PER_SLOT
            ).astype(npy.int64)
            atomic_replacement_return_counts_ref_cpu = npy.where(
                atomic_matching_slots_cpu,
                _ATOMIC_CAS_ATTEMPTS_PER_SLOT - 1,
                0
            ).astype(npy.int64)

            atomic_slot_values_gpu = cpy.array(atomic_initial_values_cpu)
            atomic_comparison_values_gpu = cpy.array(atomic_comparison_values_cpu)
            atomic_replacement_values_gpu = cpy.array(atomic_replacement_values_cpu)
            atomic_logical_attempt_count = \
                atomic_slot_count * _ATOMIC_CAS_ATTEMPTS_PER_SLOT
            atomic_returned_old_values_gpu = cpy.empty(
                atomic_logical_attempt_count, dtype=atomic_dtype_obj
            )
            _ATOMIC_CAS_TYPE_COMPAT_KERN(
                atomic_comparison_values_gpu,
                atomic_replacement_values_gpu,
                cpy.int32(_ATOMIC_CAS_ATTEMPTS_PER_SLOT),
                atomic_slot_values_gpu,
                atomic_returned_old_values_gpu,
                size=atomic_logical_attempt_count,
                block_size=_ATOMIC_CAS_BLOCK_SIZE
            )

            atomic_final_values_cpu = cpy.asnumpy(atomic_slot_values_gpu)
            atomic_returned_old_values_cpu = cpy.asnumpy(
                atomic_returned_old_values_gpu
            ).reshape((atomic_slot_count, _ATOMIC_CAS_ATTEMPTS_PER_SLOT))
            atomic_initial_return_counts_cpu = npy.count_nonzero(
                atomic_returned_old_values_cpu == atomic_initial_values_cpu[:, None],
                axis=1
            )
            atomic_replacement_return_counts_cpu = npy.count_nonzero(
                atomic_returned_old_values_cpu == atomic_replacement_values_cpu[:, None],
                axis=1
            )

            npy.testing.assert_array_equal(
                atomic_final_values_cpu,
                atomic_final_values_ref_cpu,
                strict=True
            )
            npy.testing.assert_array_equal(
                atomic_initial_return_counts_cpu,
                atomic_initial_return_counts_ref_cpu,
                strict=True
            )
            npy.testing.assert_array_equal(
                atomic_replacement_return_counts_cpu,
                atomic_replacement_return_counts_ref_cpu,
                strict=True
            )
            print(f"PASSED {atomic_case_name} atomicCAS/template test " + \
                  f"for {atomic_dtype_obj.name}! " + \
                  f"({atomic_logical_attempt_count} logical attempts)")

    npy_rng_inst = npy.random.default_rng(32928)
    mat_a_cpu = (npy_rng_inst
                   .normal(size=(_MAT_A_ROWS, _MAT_A_COLS)).astype(npy.float32))
    mat_b_cpu = (npy_rng_inst
                   .normal(size=(_MAT_A_COLS, _MAT_B_COLS)).astype(npy.float32))
    arr_one_cpu = npy_rng_inst.permutation(_ARR_LEN).astype(npy.int32)
    arr_mask_one_cpu = ((npy_rng_inst
                            .integers(low=0, high=_MASK_RAW_VAL_LIM,
                                                 size=(_ARR_LEN,)) % 2)
                                                         .astype(npy.bool_))
    arr_two_cpu = (npy_rng_inst.uniform(low=-1.0,
                                        high=npy.nextafter(1.0, 2.0),
                                        size=(_ARR_LEN,))
                                                    .astype(npy.float64))
    mat_d_cpu = (npy.arange(_MAT_D_SIZE * _MAT_D_SIZE)
                        .reshape((_MAT_D_SIZE, _MAT_D_SIZE)).astype(npy.int32))
    mat_d_idxs_rows_cpu = \
            npy_rng_inst.integers(low=0, high=_MAT_D_SIZE,
                                       size=(_MAT_D_SIZE, _MAT_D_SIZE),
                                                           dtype=npy.int32)
    mat_d_idxs_cols_cpu = \
            npy_rng_inst.integers(low=0, high=_MAT_D_SIZE,
                                       size=(_MAT_D_SIZE, _MAT_D_SIZE),
                                                           dtype=npy.int32)


    mat_a_gpu = cpy.array(mat_a_cpu)
    mat_b_gpu = cpy.array(mat_b_cpu)
    arr_one_gpu = cpy.array(arr_one_cpu)
    arr_mask_one_gpu = cpy.array(arr_mask_one_cpu)
    arr_two_gpu = cpy.array(arr_two_cpu)
    mat_d_gpu = cpy.array(mat_d_cpu)
    mat_d_idxs_rows_gpu = cpy.array(mat_d_idxs_rows_cpu)
    mat_d_idxs_cols_gpu = cpy.array(mat_d_idxs_cols_cpu)

    mat_c_gpu = mat_a_gpu @ mat_b_gpu
    arr_three_gpu = arr_one_gpu[arr_mask_one_gpu]
    arr_two_mean_gpu = arr_two_gpu.mean()
    mat_e_gpu = mat_d_gpu[mat_d_idxs_rows_gpu, mat_d_idxs_cols_gpu]

    mat_c_cpu = cpy.asnumpy(mat_c_gpu)
    arr_three_cpu = cpy.asnumpy(arr_three_gpu)
    arr_two_mean_cpu = arr_two_mean_gpu.get()
    mat_e_cpu = cpy.asnumpy(mat_e_gpu)

    mat_c_cpu_ref = mat_a_cpu @ mat_b_cpu
    arr_three_cpu_ref = arr_one_cpu[arr_mask_one_cpu]
    arr_two_mean_cpu_ref = arr_two_cpu.mean()
    mat_e_cpu_ref = mat_d_cpu[mat_d_idxs_rows_cpu, mat_d_idxs_cols_cpu]

    mat_c_cpu_fro_norm = npy.linalg.norm(mat_c_cpu)
    mat_c_cpu_ref_fro_norm = npy.linalg.norm(mat_c_cpu_ref)
    RTOL_MATMUL = 1e-7
    ATOL_MATMUL = 1e-6
    RTOL_MEAN_REDUC = 1e-10
    ATOL_MEAN_REDUC = 1e-9
    npy.testing.assert_allclose(mat_c_cpu_fro_norm,
                                mat_c_cpu_ref_fro_norm,
                                rtol=RTOL_MATMUL, atol=ATOL_MATMUL,
                                equal_nan=False, strict=True)
    print("PASSED matmuls on GPU vs CPU test! " + \
            f"(rtol={RTOL_MATMUL:.3e}, atol={ATOL_MATMUL:.3e})")
    npy.testing.assert_array_equal(arr_three_cpu,
                                   arr_three_cpu_ref,
                                           strict=True)
    print("PASSED boolean indexing on GPU vs CPU test!")
    npy.testing.assert_allclose(arr_two_mean_cpu,
                                arr_two_mean_cpu_ref,
                                rtol=RTOL_MEAN_REDUC, atol=ATOL_MEAN_REDUC,
                                equal_nan=False, strict=True)
    print("PASSED reduction of arrays to mean " + \
            f"on GPU vs CPU test! (rtol={RTOL_MEAN_REDUC:.3e}, " + \
            f"atol={ATOL_MEAN_REDUC:.3e})")
    npy.testing.assert_array_equal(mat_e_cpu,
                                   mat_e_cpu_ref,
                                           strict=True)
    print("PASSED randomized gather/scatter of " + \
            "matrix elements on GPU vs CPU test!")

    print("===== PASSED ALL NUMPY/CUPY AND CUSTOM-KERNEL SMOKE TESTS =====")
