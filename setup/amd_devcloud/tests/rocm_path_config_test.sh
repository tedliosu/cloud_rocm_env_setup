#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_funcs.sh"

expected_block() {
    # Match the literal ${PATH} written for evaluation when the profile is sourced.
    # shellcheck disable=SC2016
    printf '%s\nexport PATH="%s:${PATH}"\n%s\n' \
        "${AMD_DEVCLOUD_ROCM_PROFILE_BEGIN_MARKER}" \
        "${AMD_DEVCLOUD_ROCM_VERSIONED_BIN}" \
        "${AMD_DEVCLOUD_ROCM_PROFILE_END_MARKER}"
}

MISSING_PROFILE_HOME="${TEST_TMP_DIR}/missing-profile"
EXISTING_PROFILE_HOME="${TEST_TMP_DIR}/existing-profile"
EXACT_PROFILE_HOME="${TEST_TMP_DIR}/exact-profile"
PARTIAL_PROFILE_HOME="${TEST_TMP_DIR}/partial-profile"
DUPLICATE_PROFILE_HOME="${TEST_TMP_DIR}/duplicate-profile"
SYMLINK_PROFILE_HOME="${TEST_TMP_DIR}/symlink-profile"
SYMLINK_TARGET="${TEST_TMP_DIR}/symlink-target"
mkdir "${MISSING_PROFILE_HOME}" "${EXISTING_PROFILE_HOME}" \
    "${EXACT_PROFILE_HOME}" "${PARTIAL_PROFILE_HOME}" \
    "${DUPLICATE_PROFILE_HOME}" "${SYMLINK_PROFILE_HOME}"

ensure_amd_devcloud_rocm_path_profile "${MISSING_PROFILE_HOME}" >/dev/null
if [ "$(<"${MISSING_PROFILE_HOME}/.profile")" != "$(expected_block)" ]; then
    echo "FAILED: new profile did not contain only the exact PATH block!" >&2
    exit 1
fi
if [ "$(stat --format='%a' "${MISSING_PROFILE_HOME}/.profile")" != "644" ]; then
    echo "FAILED: new profile mode was not 0644!" >&2
    exit 1
fi

printf '%s\n' '# existing profile content' > "${EXISTING_PROFILE_HOME}/.profile"
chmod 0640 "${EXISTING_PROFILE_HOME}/.profile"
_existing_owner="$(stat --format='%u:%g' "${EXISTING_PROFILE_HOME}/.profile")"
ensure_amd_devcloud_rocm_path_profile "${EXISTING_PROFILE_HOME}" >/dev/null
printf '%s\n\n' '# existing profile content' > "${TEST_TMP_DIR}/expected-profile"
expected_block >> "${TEST_TMP_DIR}/expected-profile"
if ! cmp --silent "${EXISTING_PROFILE_HOME}/.profile" \
    "${TEST_TMP_DIR}/expected-profile"; then
    echo "FAILED: existing profile content was not preserved exactly!" >&2
    exit 1
fi
if [ "$(stat --format='%a' "${EXISTING_PROFILE_HOME}/.profile")" != "640" ]; then
    echo "FAILED: existing profile mode was not preserved!" >&2
    exit 1
fi
if [ "$(stat --format='%u:%g' "${EXISTING_PROFILE_HOME}/.profile")" != \
    "${_existing_owner}" ]; then
    echo "FAILED: existing profile ownership was not preserved!" >&2
    exit 1
fi
_existing_checksum="$(sha256sum "${EXISTING_PROFILE_HOME}/.profile")"
ensure_amd_devcloud_rocm_path_profile "${EXISTING_PROFILE_HOME}" >/dev/null
if [ "$(sha256sum "${EXISTING_PROFILE_HOME}/.profile")" != \
    "${_existing_checksum}" ]; then
    echo "FAILED: idempotent profile rerun changed the file!" >&2
    exit 1
fi

expected_block > "${EXACT_PROFILE_HOME}/.profile"
ensure_amd_devcloud_rocm_path_profile "${EXACT_PROFILE_HOME}" >/dev/null

printf '%s\n' "${AMD_DEVCLOUD_ROCM_PROFILE_BEGIN_MARKER}" \
    > "${PARTIAL_PROFILE_HOME}/.profile"
_partial_checksum="$(sha256sum "${PARTIAL_PROFILE_HOME}/.profile")"
if ensure_amd_devcloud_rocm_path_profile \
    "${PARTIAL_PROFILE_HOME}" >/dev/null 2>&1; then
    echo "FAILED: partial project-owned profile block was accepted!" >&2
    exit 1
fi
if [ "$(sha256sum "${PARTIAL_PROFILE_HOME}/.profile")" != \
    "${_partial_checksum}" ]; then
    echo "FAILED: rejected partial profile state was modified!" >&2
    exit 1
fi

expected_block > "${DUPLICATE_PROFILE_HOME}/.profile"
expected_block >> "${DUPLICATE_PROFILE_HOME}/.profile"
if ensure_amd_devcloud_rocm_path_profile \
    "${DUPLICATE_PROFILE_HOME}" >/dev/null 2>&1; then
    echo "FAILED: duplicate project-owned profile blocks were accepted!" >&2
    exit 1
fi

printf '%s\n' 'preserve target' > "${SYMLINK_TARGET}"
ln --symbolic "${SYMLINK_TARGET}" "${SYMLINK_PROFILE_HOME}/.profile"
if ensure_amd_devcloud_rocm_path_profile \
    "${SYMLINK_PROFILE_HOME}" >/dev/null 2>&1; then
    echo "FAILED: symlink profile was accepted!" >&2
    exit 1
fi
if [ "$(<"${SYMLINK_TARGET}")" != "preserve target" ]; then
    echo "FAILED: rejected symlink target was modified!" >&2
    exit 1
fi

if ensure_amd_devcloud_rocm_path_profile \
    "${TEST_TMP_DIR}/missing-home" >/dev/null 2>&1; then
    echo "FAILED: missing home directory was accepted!" >&2
    exit 1
fi
if ensure_amd_devcloud_rocm_path_profile >/dev/null 2>&1; then
    echo "FAILED: missing profile-helper argument was accepted!" >&2
    exit 1
fi
if ensure_amd_devcloud_rocm_path_profile \
    "${MISSING_PROFILE_HOME}" unexpected >/dev/null 2>&1; then
    echo "FAILED: extra profile-helper argument was accepted!" >&2
    exit 1
fi

_path_report="$(print_amd_devcloud_rocm_paths)"
if [ "${_path_report}" != \
"ROCm home for command-scoped ROCM_HOME: ${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}"$'\n'\
"ROCm executable directory: ${AMD_DEVCLOUD_ROCM_VERSIONED_BIN}"$'\n'\
"ROCm library directory for command-scoped LD_LIBRARY_PATH: ${AMD_DEVCLOUD_ROCM_VERSIONED_LIBRARY_DIR}"$'\n'\
"Current-shell PATH command: export PATH='${AMD_DEVCLOUD_ROCM_VERSIONED_BIN}':\"\${PATH}\""$'\n'\
"Workload example: env ROCM_HOME='${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}' LD_LIBRARY_PATH='${AMD_DEVCLOUD_ROCM_VERSIONED_LIBRARY_DIR}' command [arguments...]"$'\n'\
"New login shells will select the versioned executable directory after profile setup."$'\n'\
"Existing shells remain unchanged until the printed PATH command is run."$'\n'\
"Persistent ROCm runtime-selection variables are not configured." ]; then
    echo "FAILED: ROCm path report was unexpected!" >&2
    exit 1
fi
if print_amd_devcloud_rocm_paths unexpected >/dev/null 2>&1; then
    echo "FAILED: path reporter accepted an argument!" >&2
    exit 1
fi

echo "PASSED AMD DevCloud ROCm path-configuration tests!"
