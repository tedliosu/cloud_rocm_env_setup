#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
readonly REPO_ROOT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
FAKE_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly FAKE_BIN_DIR
ORIGINAL_PATH="${PATH}"
readonly ORIGINAL_PATH

# shellcheck source=../../../lib/comm_util_funcs.sh
. "${REPO_ROOT}/lib/comm_util_funcs.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${FAKE_BIN_DIR}"
cat > "${FAKE_BIN_DIR}/amd-smi" <<'EOF'
#!/bin/sh

if [ "$#" -ne 5 ] || [ "$1" != "static" ] || [ "$2" != "--gpu" ] ||
    [ "$3" != "0" ] || [ "$4" != "--asic" ] || [ "$5" != "--json" ]; then
    exit 64
fi

case ${AMD_SMI_TEST_MODE:-} in
    azure)
        printf '%s\n' '{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Radeon Pro V710 MxGPU","target_graphics_version":"gfx1101"}}]}'
        ;;
    hot_aisle)
        printf '%s\n' '{"gpu_data":[{"gpu":0,"asic":{"market_name":"AMD Instinct MI300X VF","target_graphics_version":"gfx942"}}]}'
        ;;
    missing_arch)
        printf '%s\n' '{"gpu_data":[{"gpu":0,"asic":{"market_name":"unknown"}}]}'
        ;;
    multiple_arches)
        printf '%s\n' '{"gpu_data":[{"gpu":0,"asic":{"target_graphics_version":"gfx942"}},{"gpu":0,"asic":{"target_graphics_version":"gfx1101"}}]}'
        ;;
    invalid_arch)
        printf '%s\n' '{"gpu_data":[{"gpu":0,"asic":{"target_graphics_version":"not-an-arch"}}]}'
        ;;
    malformed_json)
        printf '%s\n' '{"gpu_data":'
        ;;
    command_failure)
        exit 23
        ;;
    *)
        exit 64
        ;;
esac
EOF
chmod +x "${FAKE_BIN_DIR}/amd-smi"

expect_arch() {
    local _test_mode="$1"
    local _expected_arch="$2"
    local _actual_arch

    if ! _actual_arch=$(AMD_SMI_TEST_MODE="${_test_mode}" \
        PATH="${FAKE_BIN_DIR}:${ORIGINAL_PATH}" detect_amd_smi_gpu_arch 0); then
        echo "FAILED: '${_test_mode}' AMD SMI fixture was rejected!" >&2
        exit 1
    fi
    if [ "${_actual_arch}" != "${_expected_arch}" ]; then
        echo "FAILED: '${_test_mode}' returned '${_actual_arch}'," >&2
        echo "    expected '${_expected_arch}'!" >&2
        exit 1
    fi
}

expect_rejection() {
    local _test_mode="$1"

    if AMD_SMI_TEST_MODE="${_test_mode}" PATH="${FAKE_BIN_DIR}:${ORIGINAL_PATH}" \
        detect_amd_smi_gpu_arch 0 >/dev/null 2>&1; then
        echo "FAILED: '${_test_mode}' AMD SMI fixture was accepted!" >&2
        exit 1
    fi
}

expect_arch azure gfx1101
expect_arch hot_aisle gfx942
expect_rejection missing_arch
expect_rejection multiple_arches
expect_rejection invalid_arch
expect_rejection malformed_json
expect_rejection command_failure

if PATH="${TEST_TMP_DIR}" detect_amd_smi_gpu_arch 0 >/dev/null 2>&1; then
    echo "FAILED: missing AMD SMI command was accepted!" >&2
    exit 1
fi
if AMD_SMI_TEST_MODE=azure PATH="${FAKE_BIN_DIR}:${ORIGINAL_PATH}" \
    detect_amd_smi_gpu_arch invalid >/dev/null 2>&1; then
    echo "FAILED: invalid GPU index was accepted!" >&2
    exit 1
fi

echo "PASSED shared AMD SMI architecture detection tests!"
