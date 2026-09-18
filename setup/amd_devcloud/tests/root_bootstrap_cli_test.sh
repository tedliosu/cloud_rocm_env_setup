#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
ROOT_BOOTSTRAP="$(realpath \
    "${SCRIPT_DIR}/../bin/amd_devcloud_root_bootstrap.sh")"
TEST_TMP_DIR="$(mktemp --directory)"
TEST_KEY_FILE="${TEST_TMP_DIR}/authorized_keys"

# shellcheck source=../../../lib/comm_util_funcs.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../../../lib/comm_util_funcs.sh"
# shellcheck source=../lib/amd_devcloud_vars.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

touch "${TEST_KEY_FILE}"

"${ROOT_BOOTSTRAP}" --help >/dev/null

if "${ROOT_BOOTSTRAP}" >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted missing required arguments!" >&2
    exit 1
fi
if "${ROOT_BOOTSTRAP}" --unknown-option >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted an unknown option!" >&2
    exit 1
fi
if "${ROOT_BOOTSTRAP}" --target-user devcloud --target-user devcloud2 \
    --authorized-key-file "${TEST_KEY_FILE}" >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted a repeated target-user option!" >&2
    exit 1
fi
if "${ROOT_BOOTSTRAP}" --target-user devcloud \
    --authorized-key-file "${TEST_KEY_FILE}" \
    --authorized-key-file "${TEST_KEY_FILE}" >/dev/null 2>&1; then
    echo "FAILED: root bootstrap accepted a repeated key-file option!" >&2
    exit 1
fi

_plan_output="$("${ROOT_BOOTSTRAP}" --show-plan-only \
    --target-user devcloud \
    --authorized-key-file "${TEST_TMP_DIR}/not-created.pub")"
if ! grep --fixed-strings --quiet \
    "No account, group, SSH-key, or sudoers changes were made." \
    <<< "${_plan_output}"; then
    echo "FAILED: root-bootstrap plan mode did not report its no-change boundary!" >&2
    exit 1
fi
if grep --invert-match --extended-regexp --quiet '^\[PLAN ONLY\]' \
    <<< "${_plan_output}"; then
    echo "FAILED: root-bootstrap plan included unlabeled output!" >&2
    exit 1
fi

for _invalid_username in root _devcloud devcloud_ devcloud- DevCloud \
    'dev.cloud' 'dev cloud' $'devcloud\nother' \
    'abcdefghijklmnopqrstuvwxyzabcdefg'; do
    if "${ROOT_BOOTSTRAP}" --target-user "${_invalid_username}" \
        --authorized-key-file "${TEST_KEY_FILE}" >/dev/null 2>&1; then
        echo "FAILED: root bootstrap accepted invalid username" \
            "'${_invalid_username}'!" >&2
        exit 1
    fi
done

if [ "${EUID}" -ne 0 ]; then
    for _valid_username in a devcloud dev-cloud_2; do
        _error_output="$("${ROOT_BOOTSTRAP}" --target-user "${_valid_username}" \
            --authorized-key-file "${TEST_KEY_FILE}" 2>&1 || :)"
        if ! grep --fixed-strings --quiet \
            "AMD DevCloud root bootstrap must run as root" <<< "${_error_output}"; then
            echo "FAILED: valid username '${_valid_username}' did not reach" >&2
            echo "    the non-root invocation guard!" >&2
            exit 1
        fi
    done
    echo "SKIPPED root-only sudoers rejection scenario: not running as root."
elif os_release_matches_expected /etc/os-release \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_ID}" \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_VERSION}"; then
    _visudo_test_user="dcvisudotest${$}"
    _visudo_test_home="${AMD_DEVCLOUD_TARGET_HOME_PARENT}/${_visudo_test_user}"
    _visudo_test_sudoers="${AMD_DEVCLOUD_SUDOERS_DIR}/${AMD_DEVCLOUD_SUDOERS_FILE_PREFIX}${_visudo_test_user}"
    _visudo_test_temp_pattern="${AMD_DEVCLOUD_SUDOERS_DIR}/.${AMD_DEVCLOUD_SUDOERS_FILE_PREFIX}${_visudo_test_user}."'*'
    _visudo_test_bin="${TEST_TMP_DIR}/bin"
    _visudo_test_key="${TEST_TMP_DIR}/id_ed25519"
    _real_visudo="$(command -v visudo)"

    if getent passwd "${_visudo_test_user}" >/dev/null ||
        getent group "${_visudo_test_user}" >/dev/null ||
        [ -e "${_visudo_test_home}" ] || [ -L "${_visudo_test_home}" ] ||
        [ -e "${_visudo_test_sudoers}" ] || [ -L "${_visudo_test_sudoers}" ]; then
        echo "FAILED: visudo test target unexpectedly already exists!" >&2
        exit 1
    fi

    ssh-keygen -q -t ed25519 -N '' -f "${_visudo_test_key}"
    mkdir --parents "${_visudo_test_bin}"
    # The single-quoted positional parameters belong to the generated mock.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        'if [ "$#" -eq 1 ] && [ "$1" = "--check" ]; then' \
        "    exec '${_real_visudo}' \"\$@\"" \
        'fi' \
        'exit 1' \
        > "${_visudo_test_bin}/visudo"
    chmod +x "${_visudo_test_bin}/visudo"

    _error_output="$(PATH="${_visudo_test_bin}:${PATH}" "${ROOT_BOOTSTRAP}" \
        --target-user "${_visudo_test_user}" \
        --authorized-key-file "${_visudo_test_key}.pub" 2>&1 || :)"
    if ! grep --fixed-strings --quiet \
        "generated sudoers policy failed validation" \
        <<< "${_error_output}"; then
        echo "FAILED: root bootstrap did not reject invalid sudoers state!" >&2
        exit 1
    fi
    if compgen -G "${_visudo_test_temp_pattern}" >/dev/null; then
        echo "FAILED: sudoers rejection left temporary handoff state!" >&2
        exit 1
    fi
    if getent passwd "${_visudo_test_user}" >/dev/null ||
        getent group "${_visudo_test_user}" >/dev/null ||
        [ -e "${_visudo_test_home}" ] || [ -L "${_visudo_test_home}" ] ||
        [ -e "${_visudo_test_sudoers}" ] || [ -L "${_visudo_test_sudoers}" ]; then
        echo "FAILED: sudoers rejection changed account or project-owned state!" >&2
        exit 1
    fi
else
    echo "SKIPPED root-only sudoers rejection scenario: unsupported host OS."
fi

echo "PASSED AMD DevCloud root-bootstrap CLI tests!"
