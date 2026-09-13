#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
HANDOFF_PREFLIGHT="$(realpath \
    "${SCRIPT_DIR}/../bin/amd_devcloud_handoff_preflight.sh")"
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
TEST_TMP_DIR="$(mktemp --directory)"
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
REAL_USERNAME="$(id --user --name)"
REAL_UID="$(id --user)"
REAL_HOME="${HOME}"

# shellcheck source=../lib/amd_devcloud_vars.sh
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir --parents "${TEST_BIN_DIR}"

# Single quotes preserve the expressions for these generated command doubles.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'case "${1:-}" in' \
    '    --user)' \
    '        if [ "${2:-}" = "--name" ]; then' \
    '            printf "%s\n" "${TEST_USERNAME}"' \
    '        else' \
    '            printf "%s\n" "${TEST_UID}"' \
    '        fi' \
    '        ;;' \
    '    --groups) printf "%s\n" "${TEST_GROUPS}" ;;' \
    '    *) exit 1 ;;' \
    'esac' \
    > "${TEST_BIN_DIR}/id"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "${1:-}" = "passwd" ]' \
    '[ "${2:-}" = "${TEST_USERNAME}" ]' \
    'printf "%s:x:%s:%s::%s:%s\n" "${TEST_USERNAME}" "${TEST_UID}" "${TEST_UID}" "${TEST_HOME}" "${TEST_LOGIN_SHELL}"' \
    > "${TEST_BIN_DIR}/getent"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "${1:-}" = "-C" ]' \
    '[ "${2:-}" = "${TEST_REPO_ROOT}" ]' \
    '[ "${3:-}" = "rev-parse" ]' \
    '[ "${4:-}" = "--show-toplevel" ]' \
    '[ "${TEST_GIT_FAIL:-0}" -eq 0 ]' \
    'printf "%s\n" "${TEST_REPO_ROOT}"' \
    > "${TEST_BIN_DIR}/git"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    '[ "${TEST_SUDO_FAIL:-0}" -eq 0 ]' \
    '[ "$*" = "--non-interactive --list" ]' \
    'printf "%s\n" "${TEST_SUDO_POLICY:-(ALL : ALL) NOPASSWD: ALL}"' \
    > "${TEST_BIN_DIR}/sudo"
chmod +x "${TEST_BIN_DIR}/id" "${TEST_BIN_DIR}/getent" \
    "${TEST_BIN_DIR}/git" "${TEST_BIN_DIR}/sudo"

export PATH="${TEST_BIN_DIR}:${PATH}"
export TEST_USERNAME="${REAL_USERNAME}"
export TEST_UID="${REAL_UID}"
export TEST_HOME="${REAL_HOME}"
export TEST_LOGIN_SHELL="${AMD_DEVCLOUD_TARGET_LOGIN_SHELL}"
export TEST_REPO_ROOT="${REPO_ROOT}"
export TEST_GROUPS="${REAL_USERNAME} ${AMD_DEVCLOUD_REQUIRED_GROUPS[*]}"

"${HANDOFF_PREFLIGHT}" --help >/dev/null
if "${HANDOFF_PREFLIGHT}" unexpected >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted an unknown argument!" >&2
    exit 1
fi

_plan_output="$(TEST_UID=0 TEST_USERNAME=root TEST_SUDO_FAIL=1 \
    "${HANDOFF_PREFLIGHT}" --show-plan-only)"
if ! grep --fixed-strings --quiet \
    "No account or system state was changed." <<< "${_plan_output}"; then
    echo "FAILED: handoff-preflight plan mode did not report its boundary!" >&2
    exit 1
fi

"${HANDOFF_PREFLIGHT}" >/dev/null

if HOME=/tmp "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted the wrong login home!" >&2
    exit 1
fi
if TEST_GROUPS="${REAL_USERNAME}" \
    "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted a missing required group!" >&2
    exit 1
fi
if TEST_GIT_FAIL=1 "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted an inaccessible checkout!" >&2
    exit 1
fi
if TEST_SUDO_FAIL=1 "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted ineffective noninteractive sudo!" >&2
    exit 1
fi
if TEST_SUDO_POLICY='(ALL : ALL) NOPASSWD: /usr/bin/id' \
    "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted a narrower sudo policy!" >&2
    exit 1
fi
if TEST_SUDO_POLICY='(ALL) NOPASSWD: ALL' \
    "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted a narrower runas policy!" >&2
    exit 1
fi
if TEST_UID=0 TEST_USERNAME=root TEST_HOME=/root HOME=/root \
    "${HANDOFF_PREFLIGHT}" >/dev/null 2>&1; then
    echo "FAILED: handoff preflight accepted a root invocation!" >&2
    exit 1
fi

echo "PASSED AMD DevCloud handoff-preflight tests!"
