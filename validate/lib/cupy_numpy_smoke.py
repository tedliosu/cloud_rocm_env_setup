# pylint: disable=c-extension-no-member
"""
Smoke test to catch obvious ABI-mismatch and ROCm/CUDA GPU
    (CUB) detection related related issues with cupy <-> numpy
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
    npy.testing.assert_allclose(mat_c_cpu_fro_norm,
                                mat_c_cpu_ref_fro_norm,
                                rtol=1e-7, atol=1e-6,
                                equal_nan=False, strict=True)
    print("PASSED matmuls on GPU vs CPU test!")
    npy.testing.assert_array_equal(arr_three_cpu,
                                   arr_three_cpu_ref,
                                           strict=True)
    print("PASSED boolean indexing on GPU vs CPU test!")
    npy.testing.assert_allclose(arr_two_mean_cpu,
                                arr_two_mean_cpu_ref,
                                rtol=1e-10, atol=1e-9,
                                equal_nan=False, strict=True)
    print("PASSED reduction of arrays to mean on GPU vs CPU test!")
    npy.testing.assert_array_equal(mat_e_cpu,
                                   mat_e_cpu_ref,
                                           strict=True)
    print("PASSED randomized gather/scatter of " + \
            "matrix elements on GPU vs CPU test!")

    print("========= PASSED ALL NUMPY/CUPY SMOKE TESTS =========")
