#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
PROBE_SCRIPT="$(realpath "${SCRIPT_DIR}/../bin/amd_devcloud_acceptance_probe.sh")"
readonly PROBE_SCRIPT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_VENV_DIR="${TEST_TMP_DIR}/venv"
readonly TEST_VENV_DIR
TEST_ROCM_ROOT="${TEST_TMP_DIR}/rocm-7.2.3"
readonly TEST_ROCM_ROOT
TEST_APT_REQUIREMENTS="${TEST_TMP_DIR}/apt-requirements.txt"
readonly TEST_APT_REQUIREMENTS
TEST_OS_RELEASE="${TEST_TMP_DIR}/os-release"
readonly TEST_OS_RELEASE

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir --parents "${TEST_VENV_DIR}/bin" "${TEST_ROCM_ROOT}/bin"
printf '%s\n' 'ID=ubuntu' 'VERSION_ID="24.04"' \
    'PRETTY_NAME="Ubuntu 24.04.4 LTS"' > "${TEST_OS_RELEASE}"
printf '%s\n' git jq > "${TEST_APT_REQUIREMENTS}"

# Single quotes preserve these expressions for the generated command doubles.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'if [ "${1:-}" = "--version" ]; then' \
    '    printf "%s\n" "Python 3.12.3"' \
    'elif [ "$*" = "-m pip freeze --all" ]; then' \
    '    printf "%s\n" "pip==25.2" "torch==2.11.0+rocm7.2"' \
    'else' \
    '    exit 91' \
    'fi' > "${TEST_VENV_DIR}/bin/python"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$*" = "--version" ]' \
    '[ "${TEST_HIPCONFIG_STATUS:-0}" -eq 0 ] || exit "${TEST_HIPCONFIG_STATUS}"' \
    'printf "%s\n" "HIP version: 7.2.53210"' \
    > "${TEST_ROCM_ROOT}/bin/hipconfig"
chmod +x "${TEST_VENV_DIR}/bin/python" \
    "${TEST_ROCM_ROOT}/bin/hipconfig"

date() {
    [ "$*" = "--utc +%Y-%m-%dT%H:%M:%SZ" ]
    printf '%s\n' '2026-09-14T18:30:00Z'
}

uname() {
    [ "$*" = "--kernel-release --machine" ]
    printf '%s\n' '6.8.0-124-generic x86_64'
}

python3() {
    [ "$*" = "--version" ]
    printf '%s\n' 'Python 3.12.3'
}

dpkg-query() {
    [ "${1:-}" = "--show" ]
    case " $* " in
        *" ${AMD_DEVCLOUD_ROCM_METAPACKAGE} "*)
            printf '%s\t%s\n' \
                amdgpu-dkms "${AMD_DEVCLOUD_AMDGPU_DKMS_PACKAGE_VERSION}" \
                rocm7.2.3 "${AMD_DEVCLOUD_ROCM_METAPACKAGE_VERSION}"
            ;;
        *)
            printf '%s\t%s\n' cmake 4.4.2 git 1:2.43.0 jq 1.7.1
            ;;
    esac
}

verify_amd_devcloud_post_driver_state_dont_wrap() {
    printf '%s\n' \
        'AMD DevCloud post-driver verification passed.' \
        'AMDGPU DKMS: 6.16.13-2327507.24.04 (installed)' \
        'GPU: AMD Instinct MI300X VF (gfx942)' \
        'AMD SMI driver version: 6.16.13'
}

export TEST_HIPCONFIG_STATUS=0
_record="$(print_amd_devcloud_acceptance_record \
    "${TEST_OS_RELEASE}" "${TEST_VENV_DIR}" \
    "${TEST_APT_REQUIREMENTS}" "${TEST_ROCM_ROOT}")"
for _expected_text in \
    'Recorded UTC: 2026-09-14T18:30:00Z' \
    'PRETTY_NAME="Ubuntu 24.04.4 LTS"' \
    '6.8.0-124-generic x86_64' \
    'GPU: AMD Instinct MI300X VF (gfx942)' \
    'HIP version: 7.2.53210' \
    'Baseline: Python 3.12.3' \
    'torch==2.11.0+rocm7.2'; do
    if ! grep --fixed-strings --quiet "${_expected_text}" <<< "${_record}"; then
        echo "FAILED: acceptance probe omitted '${_expected_text}'!" >&2
        exit 1
    fi
done

TEST_HIPCONFIG_STATUS=23
export TEST_HIPCONFIG_STATUS
if print_amd_devcloud_acceptance_record \
    "${TEST_OS_RELEASE}" "${TEST_VENV_DIR}" \
    "${TEST_APT_REQUIREMENTS}" "${TEST_ROCM_ROOT}" >/dev/null 2>&1; then
    echo "FAILED: acceptance probe accepted a failed ROCm observation!" >&2
    exit 1
fi

TEST_HIPCONFIG_STATUS=0
export TEST_HIPCONFIG_STATUS
printf '%s\n' 'bad package name' > "${TEST_APT_REQUIREMENTS}"
if print_amd_devcloud_acceptance_record \
    "${TEST_OS_RELEASE}" "${TEST_VENV_DIR}" \
    "${TEST_APT_REQUIREMENTS}" "${TEST_ROCM_ROOT}" >/dev/null 2>&1; then
    echo "FAILED: acceptance probe accepted an invalid package name!" >&2
    exit 1
fi
if print_amd_devcloud_acceptance_record one two three >/dev/null 2>&1; then
    echo "FAILED: acceptance probe accepted the wrong argument count!" >&2
    exit 1
fi

"${PROBE_SCRIPT}" --help >/dev/null
if "${PROBE_SCRIPT}" --unknown >/dev/null 2>&1; then
    echo "FAILED: acceptance probe script accepted an unknown option!" >&2
    exit 1
fi

echo "PASSED AMD DevCloud acceptance-probe tests!"
