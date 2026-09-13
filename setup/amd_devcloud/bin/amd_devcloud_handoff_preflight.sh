#!/bin/bash

set -euo pipefail

readonly SHOW_PLAN_ONLY_FLAG="--show-plan-only"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../../..")"
readonly REPO_ROOT

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"

usage() {
    echo "Usage: $0 [${SHOW_PLAN_ONLY_FLAG}] [-h|--help]"
}

while [ "$#" -gt 0 ]; do
    case $1 in
        "${SHOW_PLAN_ONLY_FLAG}")
            export SHOW_PLAN_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$1'!" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
    echo "[PLAN ONLY] Would verify the ordinary-user identity, home, shell,"
    echo "[PLAN ONLY]     effective required groups, repository access, and"
    echo "[PLAN ONLY]     full noninteractive sudo contract."
    echo "[PLAN ONLY] No account or system state was changed."
    exit 0
fi

for _required_command in getent git grep id realpath sudo; do
    command -v "${_required_command}" >/dev/null 2>&1 || {
        echo "ERROR: required command '${_required_command}' is unavailable!" >&2
        exit 1
    }
done

_effective_uid="$(id --user)" || {
    echo "ERROR: unable to determine the effective user ID!" >&2
    exit 1
}
_effective_user="$(id --user --name)" || {
    echo "ERROR: unable to determine the effective username!" >&2
    exit 1
}
if [ "${_effective_uid}" -eq 0 ] || [ "${_effective_user}" = "root" ]; then
    echo "ERROR: AMD DevCloud handoff preflight must run as the ordinary user!" >&2
    exit 1
fi

_passwd_entry="$(getent passwd "${_effective_user}")" || {
    echo "ERROR: unable to read the current user's account entry!" >&2
    exit 1
}
IFS=: read -r _passwd_name _passwd_unused _passwd_uid _passwd_gid \
    _passwd_gecos _passwd_home _passwd_shell <<< "${_passwd_entry}"
_expected_home="${AMD_DEVCLOUD_TARGET_HOME_PARENT}/${_effective_user}"
if [ "${_passwd_name}" != "${_effective_user}" ] ||
    [ "${_passwd_uid}" != "${_effective_uid}" ] ||
    [ "${_passwd_home}" != "${_expected_home}" ] ||
    [ "${_passwd_shell}" != "${AMD_DEVCLOUD_TARGET_LOGIN_SHELL}" ]; then
    echo "ERROR: the current account does not match the expected DevCloud" >&2
    echo "    ordinary-user identity, home, and shell!" >&2
    exit 1
fi
if [ "${HOME:-}" != "${_expected_home}" ] ||
    [ ! -d "${_expected_home}" ] || [ -L "${_expected_home}" ]; then
    echo "ERROR: the current login does not have the expected real home" >&2
    echo "    directory '${_expected_home}'!" >&2
    exit 1
fi

_effective_groups="$(id --groups --name)" || {
    echo "ERROR: unable to determine effective group membership!" >&2
    exit 1
}
for _required_group in "${AMD_DEVCLOUD_REQUIRED_GROUPS[@]}"; do
    case " ${_effective_groups} " in
        *" ${_required_group} "*) ;;
        *)
            echo "ERROR: required group '${_required_group}' is not effective" >&2
            echo "    in this login session!" >&2
            exit 1
            ;;
    esac
done

if [ ! -x "${REPO_ROOT}" ] || [ ! -r "${REPO_ROOT}/README.md" ]; then
    echo "ERROR: the current user cannot access the repository checkout!" >&2
    exit 1
fi
_git_top_level="$(git -C "${REPO_ROOT}" rev-parse --show-toplevel)" || {
    echo "ERROR: the preflight script is not in an accessible Git checkout!" >&2
    exit 1
}
_git_top_level="$(realpath "${_git_top_level}")" || {
    echo "ERROR: unable to resolve the Git checkout path!" >&2
    exit 1
}
if [ "${_git_top_level}" != "${REPO_ROOT}" ]; then
    echo "ERROR: resolved Git checkout does not match the script repository!" >&2
    exit 1
fi

# Inspect the effective policy without changing sudo credential timestamps or
#     executing a privileged command. Accept the spacing emitted by supported
#     sudo versions while requiring the selected full NOPASSWD contract.
_sudo_listing="$(LC_ALL=C sudo --non-interactive --list)" || {
    echo "ERROR: unable to inspect the effective noninteractive sudo policy!" >&2
    exit 1
}
if ! printf '%s\n' "${_sudo_listing}" | grep --extended-regexp --quiet \
    "${AMD_DEVCLOUD_SUDO_LIST_POLICY_REGEX}"; then
    echo "ERROR: the effective sudo policy does not grant the selected full" >&2
    echo "    NOPASSWD contract!" >&2
    exit 1
fi

echo "AMD DevCloud ordinary-user handoff preflight passed."
echo "User: ${_effective_user}"
echo "Home: ${_expected_home}"
echo "Repository: ${REPO_ROOT}"
echo "Required groups are effective and full noninteractive sudo is available."
echo "This preflight does not claim that ROCm or GPU access is ready."
