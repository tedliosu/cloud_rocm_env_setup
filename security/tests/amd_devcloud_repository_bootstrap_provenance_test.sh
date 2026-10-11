#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
readonly REPO_ROOT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly TEST_BIN_DIR

cleanup() {
    rm --recursive --force -- "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--fail" ]' \
    '[ "$2" = "--silent" ]' \
    '[ "$3" = "--show-error" ]' \
    '[ "$4" = "--location" ]' \
    '[ "$5" = "--proto" ]' \
    '[ "$6" = "=https" ]' \
    '[ "$7" = "--proto-redir" ]' \
    '[ "$8" = "=https" ]' \
    '[ "$9" = "--output" ]' \
    '[ "${11}" = "--write-out" ]' \
    '[ "${12}" = "%{url_effective}" ]' \
    '[ "${13}" = "${TEST_BOOTSTRAP_URL}" ]' \
    '[ "${TEST_CURL_STATUS}" -eq 0 ] || exit "${TEST_CURL_STATUS}"' \
    'printf "mock AMD package\n" > "${10}"' \
    'printf "%s" "${TEST_EFFECTIVE_URL}"' \
    > "${TEST_BIN_DIR}/curl"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$*" = "--check --status" ]' \
    'IFS= read -r checksum_line' \
    'case "${checksum_line}" in "${TEST_BOOTSTRAP_SHA256}  "*) ;; *) exit 64 ;; esac' \
    'exit "${TEST_SHA256_STATUS}"' \
    > "${TEST_BIN_DIR}/sha256sum"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "$1" = "--field" ]' \
    '[ "$3" = "Version" ]' \
    '[ "${TEST_DPKG_DEB_STATUS}" -eq 0 ] || exit "${TEST_DPKG_DEB_STATUS}"' \
    'printf "%s\n" "${TEST_PACKAGE_METADATA_VERSION}"' \
    > "${TEST_BIN_DIR}/dpkg-deb"

chmod +x "${TEST_BIN_DIR}"/*
export PATH="${TEST_BIN_DIR}:/usr/bin:/bin"

# shellcheck source=../../setup/amd_devcloud/lib/amd_devcloud_vars.sh
. "${REPO_ROOT}/setup/amd_devcloud/lib/amd_devcloud_vars.sh"

export TEST_BOOTSTRAP_URL="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}"
export TEST_BOOTSTRAP_SHA256="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_SHA256}"

reset_observations() {
    TEST_CURL_STATUS=0
    TEST_EFFECTIVE_URL="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}"
    TEST_SHA256_STATUS=0
    TEST_DPKG_DEB_STATUS=0
    TEST_PACKAGE_METADATA_VERSION="${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}"
    export TEST_CURL_STATUS TEST_EFFECTIVE_URL TEST_SHA256_STATUS
    export TEST_DPKG_DEB_STATUS TEST_PACKAGE_METADATA_VERSION
}

expect_rejection() {
    local _description="$1"

    if "${REPO_ROOT}/security/check_amd_devcloud_repository_bootstrap.sh" \
        >/dev/null 2>&1; then
        echo "FAILED: ${_description} was accepted!" >&2
        exit 1
    fi
}

reset_observations
"${REPO_ROOT}/security/check_amd_devcloud_repository_bootstrap.sh" >/dev/null

reset_observations
TEST_CURL_STATUS=22
export TEST_CURL_STATUS
expect_rejection "failed provenance download"

reset_observations
TEST_EFFECTIVE_URL="https://unexpected.example/amdgpu-install.deb"
export TEST_EFFECTIVE_URL
expect_rejection "unexpected redirect destination"

reset_observations
TEST_SHA256_STATUS=1
export TEST_SHA256_STATUS
expect_rejection "changed artifact digest"

reset_observations
TEST_PACKAGE_METADATA_VERSION="unexpected"
export TEST_PACKAGE_METADATA_VERSION
expect_rejection "changed package version"

echo "PASSED AMD DevCloud repository-bootstrap provenance tests!"
