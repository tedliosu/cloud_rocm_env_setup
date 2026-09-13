#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

TEST_KERNEL_RELEASE="6.8.0-124-generic"
TEST_MACHINE_ARCH="${AMD_DEVCLOUD_EXPECTED_DKMS_ARCH}"
TEST_PCI_OUTPUT=$'0000:83:00.0 1200: 1002:74b5\n'
TEST_DKMS_OUTPUT=""
TEST_AMD_SMI_JSON=""
TEST_LSPCI_STATUS=0
TEST_UNAME_STATUS=0
TEST_DKMS_STATUS=0
TEST_AMD_SMI_STATUS=0
TEST_AMD_SMI_EXECUTABLE=1
TEST_AMDGPU_LOADED=1
TEST_KFD_PRESENT=1

lspci() {
    [ "$*" = "-Dn -d ${AMD_DEVCLOUD_EXPECTED_BARE_PCI_DEVICE_ID}" ] ||
        return 64
    [ "${TEST_LSPCI_STATUS}" -eq 0 ] || return "${TEST_LSPCI_STATUS}"
    printf '%s' "${TEST_PCI_OUTPUT}"
}

uname() {
    [ "${TEST_UNAME_STATUS}" -eq 0 ] || return "${TEST_UNAME_STATUS}"
    case ${1:-} in
        --kernel-release)
            printf '%s\n' "${TEST_KERNEL_RELEASE}"
            ;;
        --machine)
            printf '%s\n' "${TEST_MACHINE_ARCH}"
            ;;
        *)
            return 64
            ;;
    esac
}

dkms() {
    [ "$*" = "status amdgpu/${AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION} -k ${TEST_KERNEL_RELEASE}/${TEST_MACHINE_ARCH}" ] ||
        return 64
    [ "${TEST_DKMS_STATUS}" -eq 0 ] || return "${TEST_DKMS_STATUS}"
    printf '%s\n' "${TEST_DKMS_OUTPUT}"
}

_amd_devcloud_amdgpu_module_is_loaded() {
    [ "${TEST_AMDGPU_LOADED}" -eq 1 ]
}

_amd_devcloud_kfd_is_present() {
    [ "${TEST_KFD_PRESENT}" -eq 1 ]
}

_amd_devcloud_amd_smi_is_executable() {
    [ "${TEST_AMD_SMI_EXECUTABLE}" -eq 1 ]
}

_amd_devcloud_run_amd_smi_static() {
    [ "${TEST_AMD_SMI_STATUS}" -eq 0 ] || return "${TEST_AMD_SMI_STATUS}"
    printf '%s\n' "${TEST_AMD_SMI_JSON}"
}

reset_observations() {
    TEST_KERNEL_RELEASE="6.8.0-124-generic"
    TEST_MACHINE_ARCH="${AMD_DEVCLOUD_EXPECTED_DKMS_ARCH}"
    TEST_PCI_OUTPUT=$'0000:83:00.0 1200: 1002:74b5\n'
    TEST_DKMS_OUTPUT="amdgpu/${AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION}, ${TEST_KERNEL_RELEASE}, ${TEST_MACHINE_ARCH}: installed"
    TEST_AMD_SMI_JSON='{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":"6.16.13"}}]}'
    TEST_LSPCI_STATUS=0
    TEST_UNAME_STATUS=0
    TEST_DKMS_STATUS=0
    TEST_AMD_SMI_STATUS=0
    TEST_AMD_SMI_EXECUTABLE=1
    TEST_AMDGPU_LOADED=1
    TEST_KFD_PRESENT=1
    unset SHOW_PLAN_ONLY
}

expect_acceptance() {
    local _output

    # shellcheck disable=SC2119 # Exercise the documented zero-argument interface.
    if ! _output="$(verify_amd_devcloud_post_driver_state_dont_wrap)"; then
        echo "FAILED: expected post-driver verification acceptance!" >&2
        exit 1
    fi
    if ! grep --fixed-strings --quiet \
        "AMD SMI driver version: 6.16.13" <<< "${_output}"; then
        echo "FAILED: post-driver verification omitted the observed driver!" >&2
        exit 1
    fi
}

expect_rejection() {
    # shellcheck disable=SC2119 # The production function deliberately rejects failures.
    if verify_amd_devcloud_post_driver_state_dont_wrap >/dev/null 2>&1; then
        echo "FAILED: expected post-driver verification rejection!" >&2
        exit 1
    fi
}

reset_observations
expect_acceptance

reset_observations
TEST_AMDGPU_LOADED=0
expect_rejection

reset_observations
TEST_KFD_PRESENT=0
expect_rejection

reset_observations
TEST_PCI_OUTPUT=""
expect_rejection

reset_observations
TEST_PCI_OUTPUT+=$'0000:84:00.0 1200: 1002:74b5\n'
expect_rejection

reset_observations
TEST_MACHINE_ARCH="aarch64"
expect_rejection

reset_observations
TEST_DKMS_OUTPUT="amdgpu/${AMD_DEVCLOUD_AMDGPU_DKMS_MODULE_VERSION}, ${TEST_KERNEL_RELEASE}, ${TEST_MACHINE_ARCH}: built"
expect_rejection

reset_observations
TEST_DKMS_STATUS=23
expect_rejection

reset_observations
TEST_AMD_SMI_EXECUTABLE=0
expect_rejection

reset_observations
TEST_AMD_SMI_STATUS=24
expect_rejection

reset_observations
TEST_AMD_SMI_JSON='{"gpu_data":['
expect_rejection

reset_observations
TEST_AMD_SMI_JSON='{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":"6.16.13"}},{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":"6.16.13"}}]}'
expect_rejection

reset_observations
TEST_AMD_SMI_JSON=$'{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":"6.16.13"}}]}\n{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":"6.16.13"}}]}'
expect_rejection

reset_observations
TEST_AMD_SMI_JSON='{"gpu_data":[{"gpu":0,"asic":{"market_name":"unexpected","target_graphics_version":"gfx942"},"driver":{"version":"6.16.13"}}]}'
expect_rejection

reset_observations
TEST_AMD_SMI_JSON='{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx1101"},"driver":{"version":"6.16.13"}}]}'
expect_rejection

reset_observations
TEST_AMD_SMI_JSON='{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":""}}]}'
expect_rejection

reset_observations
TEST_AMD_SMI_JSON='{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"},"driver":{"version":"unexpected"}}]}'
expect_rejection

reset_observations
SHOW_PLAN_ONLY=1
TEST_LSPCI_STATUS=25
TEST_UNAME_STATUS=26
TEST_DKMS_STATUS=27
TEST_AMD_SMI_STATUS=28
TEST_AMD_SMI_EXECUTABLE=0
TEST_AMDGPU_LOADED=0
TEST_KFD_PRESENT=0
# shellcheck disable=SC2119 # Exercise the documented zero-argument interface.
_plan_output="$(verify_amd_devcloud_post_driver_state_dont_wrap)"
if grep --invert-match --extended-regexp --quiet '^\[PLAN ONLY\]' \
    <<< "${_plan_output}"; then
    echo "FAILED: post-driver plan included unlabeled output!" >&2
    exit 1
fi

if verify_amd_devcloud_post_driver_state_dont_wrap unexpected \
    >/dev/null 2>&1; then
    echo "FAILED: post-driver verifier accepted an argument!" >&2
    exit 1
fi

echo "PASSED AMD DevCloud post-driver verification tests!"
