/*
 * Smoke test to catch obvious errors relating to compiling and running any
 * program containing a slightly non-trivial HIP kernel and HIP-based logic.
 */
#include <hip/hip_runtime.h>
#include <thrust/device_vector.h>
#include <thrust/logical.h>
#include <thrust/memory.h>
#include <thrust/sequence.h>
#include <thrust/transform.h>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <string_view>

#define HIP_CHECK_ERR(call)                                         \
  {                                                                 \
    hipError_t err = (call);                                        \
    if (err != hipSuccess) {                                        \
      std::cerr << "Got error " << hipGetErrorString(err) << " at " \
                << __FILE__ << ":" << __LINE__ << "\n";             \
      std::exit(EXIT_FAILURE);                                      \
    }                                                               \
  }

constexpr int64_t ARRAY_CHUNK_LEN = 256;
constexpr int32_t NUM_THREADBLOCKS = 8;
constexpr int32_t THREADS_PER_BLOCK = 64;
constexpr double SEQ_INIT = 0.0;
constexpr double SEQ_STEP = 0.1;
constexpr double FRAC_LAST_CHUNK = 0.66;

static_assert(ARRAY_CHUNK_LEN % static_cast<int64_t>(THREADS_PER_BLOCK) == 0);
constexpr int64_t NUM_PER_THREAD_ARR =
    ARRAY_CHUNK_LEN / static_cast<int64_t>(THREADS_PER_BLOCK);

// ChatGPT assisted helper class for getting current HIP device ID/name
class hip_device {
 public:
  // Returns the currently selected HIP device, or nullopt on failure.
  static std::optional<hip_device> current() noexcept {
    int id = 0;
    if (hipGetDevice(&id) != hipSuccess)
      return std::nullopt;

    hipDeviceProp_t prop{};
    if (hipGetDeviceProperties(&prop, id) != hipSuccess)
      return std::nullopt;

    return hip_device{id, prop};
  }

  int id() const noexcept { return id_; }

  // prop_.name is a fixed-size C string stored inside hipDeviceProp_t.
  std::string_view name() const noexcept { return prop_.name; }

 private:
  int id_{-1};
  hipDeviceProp_t prop_{};

  hip_device(int id, const hipDeviceProp_t& prop) noexcept
      : id_(id), prop_(prop) {}
};

__global__ void test_small_copy_kern(double* sample_data_in,
                                     double* sample_data_out,
                                     int64_t total_arr_len) {
  __shared__ double lds_buff[ARRAY_CHUNK_LEN];
  double thread_local_buff[NUM_PER_THREAD_ARR];

  for (int64_t first_thread_pos_buff = 0;
       first_thread_pos_buff < ARRAY_CHUNK_LEN;
       first_thread_pos_buff += blockDim.x) {
    if (blockIdx.x * ARRAY_CHUNK_LEN + first_thread_pos_buff + threadIdx.x <
        total_arr_len) {
      lds_buff[first_thread_pos_buff + threadIdx.x] =
          sample_data_in[blockIdx.x * ARRAY_CHUNK_LEN + first_thread_pos_buff +
                         threadIdx.x];
    }
  }

  __syncthreads();

  for (int64_t first_thread_pos_buff = 0;
       first_thread_pos_buff < ARRAY_CHUNK_LEN;
       first_thread_pos_buff += blockDim.x) {
    if (blockIdx.x * ARRAY_CHUNK_LEN + first_thread_pos_buff + threadIdx.x <
        total_arr_len) {
      thread_local_buff[(first_thread_pos_buff + threadIdx.x) / blockDim.x] =
          lds_buff[first_thread_pos_buff + threadIdx.x];
    }
  }

  __syncthreads();

  for (int64_t first_thread_pos_buff = 0;
       first_thread_pos_buff < ARRAY_CHUNK_LEN;
       first_thread_pos_buff += blockDim.x) {
    if (blockIdx.x * ARRAY_CHUNK_LEN + first_thread_pos_buff + threadIdx.x <
        total_arr_len) {
      sample_data_out[blockIdx.x * ARRAY_CHUNK_LEN + first_thread_pos_buff +
                      threadIdx.x] =
          thread_local_buff[(first_thread_pos_buff + threadIdx.x) / blockDim.x];
    }
  }
}

int main(void) {
  int64_t arr_len = static_cast<int64_t>(std::floor(
      (static_cast<double>(ARRAY_CHUNK_LEN) *
       (static_cast<double>(NUM_THREADBLOCKS - 1) + FRAC_LAST_CHUNK))));

  auto dev_inst = hip_device::current();
  std::cout << "Current HIP Device Name: " << dev_inst->name() << "\n";

  thrust::device_vector<double> input_vec_dev(
      static_cast<std::size_t>(arr_len));
  thrust::device_vector<double> output_vec_dev(
      static_cast<std::size_t>(arr_len));
  thrust::device_vector<bool> elem_wise_comp_vec_dev(
      static_cast<std::size_t>(arr_len));

  thrust::sequence(input_vec_dev.begin(), input_vec_dev.end(), SEQ_INIT,
                   SEQ_STEP);

  dim3 grid_size(NUM_THREADBLOCKS, 1, 1);
  dim3 block_size(THREADS_PER_BLOCK, 1, 1);
  const void* kernel_func_ptr =
      reinterpret_cast<const void*>(test_small_copy_kern);
  double* input_vec_dev_rwptr = thrust::raw_pointer_cast(input_vec_dev.data());
  double* output_vec_dev_rwptr =
      thrust::raw_pointer_cast(output_vec_dev.data());
  void* custom_copy_kernel_args[] = {&input_vec_dev_rwptr,
                                     &output_vec_dev_rwptr, &arr_len};

  HIP_CHECK_ERR(hipLaunchKernel(kernel_func_ptr, grid_size, block_size,
                                custom_copy_kernel_args, 0, NULL));
  HIP_CHECK_ERR(hipDeviceSynchronize());

  thrust::transform(
      input_vec_dev.begin(), input_vec_dev.end(), output_vec_dev.begin(),
      elem_wise_comp_vec_dev.begin(),
      [] __device__(double in_vec_elem, double out_vec_elem) -> bool {
        return in_vec_elem <= out_vec_elem && in_vec_elem >= out_vec_elem;
      });
  bool is_all_true =
      thrust::all_of(elem_wise_comp_vec_dev.begin(),
                     elem_wise_comp_vec_dev.end(), ::internal::identity());

  int exit_code = EXIT_FAILURE;
  constexpr std::string_view TEST_OBJ_STR = "test for basic custom copy kernel";
  if (is_all_true) {
    std::cout << "PASSED " << TEST_OBJ_STR << "!\n";
    exit_code = EXIT_SUCCESS;
  } else {
    std::cerr << "FAILED " << TEST_OBJ_STR << "!\n";
  }

  std::exit(exit_code);
}
