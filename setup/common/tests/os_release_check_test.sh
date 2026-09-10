#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
readonly REPO_ROOT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR

# shellcheck source=../../../lib/comm_util_funcs.sh
. "${REPO_ROOT}/lib/comm_util_funcs.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

write_os_release() {
    local _fixture_name="$1"
    shift

    printf '%s\n' "$@" > "${TEST_TMP_DIR}/${_fixture_name}"
}

expect_match() {
    local _fixture_name="$1"

    if ! os_release_matches_expected "${TEST_TMP_DIR}/${_fixture_name}" \
        ubuntu 24.04; then
        echo "FAILED: '${_fixture_name}' did not match Ubuntu 24.04!" >&2
        exit 1
    fi
}

expect_rejection() {
    local _fixture_name="$1"

    if os_release_matches_expected "${TEST_TMP_DIR}/${_fixture_name}" \
        ubuntu 24.04; then
        echo "FAILED: '${_fixture_name}' incorrectly matched Ubuntu 24.04!" >&2
        exit 1
    fi
}

write_os_release ubuntu_quoted \
    'NAME="Ubuntu"' \
    'VERSION_ID="24.04"' \
    'ID=ubuntu'
expect_match ubuntu_quoted

write_os_release ubuntu_unquoted \
    'ID=ubuntu' \
    'VERSION_ID=24.04'
expect_match ubuntu_unquoted

# Representative Fedora Server fields verify conservative distro rejection.
write_os_release fedora_server \
    'NAME="Fedora Linux"' \
    'VERSION="44 (Server Edition)"' \
    'RELEASE_TYPE=stable' \
    'ID=fedora' \
    'VERSION_ID=44' \
    'PRETTY_NAME="Fedora Linux 44 (Server Edition)"'
expect_rejection fedora_server

write_os_release wrong_ubuntu_version \
    'ID=ubuntu' \
    'VERSION_ID="22.04"'
expect_rejection wrong_ubuntu_version

write_os_release missing_id \
    'NAME="Ubuntu"' \
    'VERSION_ID="24.04"'
expect_rejection missing_id

write_os_release missing_version \
    'NAME="Ubuntu"' \
    'ID=ubuntu'
expect_rejection missing_version

write_os_release duplicate_id \
    'ID=ubuntu' \
    'ID=ubuntu' \
    'VERSION_ID="24.04"'
expect_rejection duplicate_id

write_os_release duplicate_version \
    'ID=ubuntu' \
    'VERSION_ID="24.04"' \
    'VERSION_ID=24.04'
expect_rejection duplicate_version

if os_release_matches_expected "${TEST_TMP_DIR}/missing" ubuntu 24.04; then
    echo "FAILED: a missing os-release file matched Ubuntu 24.04!" >&2
    exit 1
fi

echo "PASSED shared os-release identity tests!"
