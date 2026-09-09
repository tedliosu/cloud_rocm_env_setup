"""
Smoke test to catch obvious ABI-mismatch and TBB (oneAPI)
    detection related related issues with numba <-> numpy
"""
import sys
from numba import njit, prange
import numba
import numpy.typing as np_typ
import numpy as npy


_ELU_ALPHA_CONST: float = 1.8
_MAT_A_ROWS: int = 784
_MAT_A_COLS: int = 512

def elu_forward_ref(input_arr: np_typ.NDArray[npy.floating]) -> \
                                        np_typ.NDArray[npy.floating]:
    """
    Reference implementation of ELU activation function,
        forward pass
    """
    return npy.where(input_arr > 0,
                     input_arr,
                     _ELU_ALPHA_CONST * npy.expm1(input_arr))

@njit(cache=True, parallel=True, nogil=True,
          inline="always", forceinline=True, fastmath=True)
def elu_forward_prange(input_arr):
    """
    Numba prange based implementation of ELU activation function,
        forward pass; function is NOT type annotated because
        there have been reports of python native type hinting
        conflicting with the numba compiler
    """
    unraveled_len = input_arr.size
    preact_raveled_arr = input_arr.ravel()
    res_arr = npy.empty_like(input_arr)
    res_raveled_arr = res_arr.ravel()
    for idx in prange(unraveled_len): # pylint: disable=not-an-iterable
        res_raveled_arr[idx] = \
                npy.where(preact_raveled_arr[idx] > 0,
                          preact_raveled_arr[idx],
                          _ELU_ALPHA_CONST * \
                              npy.expm1(preact_raveled_arr[idx]))
    return res_raveled_arr.reshape(input_arr.shape)


if __name__ == "__main__":

    # pylint: disable=invalid-name
    python_ver_str = sys.version.replace("\n", " ")
    print("=== Relevant Environment Info of Versions ===")
    print(f"python: {python_ver_str}")
    print(f"numpy: {npy.__version__}")
    print(f"numba: {numba.__version__}")

    npy_rng_inst = npy.random.default_rng(32928)
    mat_a_cpu = (npy_rng_inst
                   .normal(size=(_MAT_A_ROWS, _MAT_A_COLS)).astype(npy.float32))

    mat_b_cpu = elu_forward_prange(mat_a_cpu)

    mat_b_cpu_ref = elu_forward_ref(mat_a_cpu)

    mat_b_cpu_fro_norm = npy.linalg.norm(mat_b_cpu)
    mat_b_cpu_ref_fro_norm = npy.linalg.norm(mat_b_cpu_ref)
    RTOL_ELU_FORWARD = 1e-7
    ATOL_ELU_FORWARD = 1e-6
    npy.testing.assert_allclose(mat_b_cpu_fro_norm,
                                mat_b_cpu_ref_fro_norm,
                                rtol=RTOL_ELU_FORWARD,
                                atol=ATOL_ELU_FORWARD,
                                equal_nan=False, strict=True)
    print("PASSED ELU forward pass with matrix on CPU test! " + \
            f"(rtol={RTOL_ELU_FORWARD:.3e}, atol={ATOL_ELU_FORWARD:.3e})")

    selected_threading_layer = numba.threading_layer()
    if selected_threading_layer != "tbb":
        raise RuntimeError("Expected Numba threading layer 'tbb', " +
                           f"got '{selected_threading_layer}' instead")
    print("PASSED Numba TBB threading-layer selection test!")

    print("========= PASSED ALL NUMPY/NUMBA SMOKE TESTS =========")
