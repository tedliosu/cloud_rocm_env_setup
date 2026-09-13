#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/..")"
readonly REPO_ROOT

readonly -a LOCAL_TESTS=(
    setup/amd_devcloud/tests/env_setup_plan_test.sh
    setup/amd_devcloud/tests/handoff_preflight_test.sh
    setup/amd_devcloud/tests/repository_bootstrap_test.sh
    setup/amd_devcloud/tests/system_upgrade_admission_test.sh
    setup/amd_devcloud/tests/root_bootstrap_cli_test.sh
    setup/common/tests/amd_smi_arch_test.sh
    setup/common/tests/cupy_wheel_failure_test.sh
    setup/common/tests/group_relogin_test.sh
    setup/common/tests/guarded_rm_rf_test.sh
    setup/common/tests/os_release_check_test.sh
    setup/common/tests/reboot_ack_test.sh
    setup/common/tests/rocm_sanity_test.sh
    setup/common/tests/setup_cli_test.sh
    setup/common/tests/stage_failure_test.sh
    setup/common/tests/ufw_classifier_test.sh
    setup/common/tests/ufw_defaults_selector_test.sh
    validate/tests/plain_filename_test.sh
    validate/tests/source_built_cupy_gate_test.sh
    validate/tests/triton_failure_test.sh
)

for _test_file in "${LOCAL_TESTS[@]}"; do
    echo "--- running ${_test_file} ---"
    bash "${REPO_ROOT}/${_test_file}"
done

echo "PASSED all ${#LOCAL_TESTS[@]} repository-local shell tests!"
