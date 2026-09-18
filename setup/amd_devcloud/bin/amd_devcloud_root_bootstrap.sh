#!/bin/bash

set -euo pipefail

readonly TARGET_USER_FLAG="--target-user"
readonly AUTHORIZED_KEY_FILE_FLAG="--authorized-key-file"
readonly SHOW_PLAN_ONLY_FLAG="--show-plan-only"
readonly TARGET_USERNAME_REGEX='^[a-z]([a-z0-9_-]{0,30}[a-z0-9])?$'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR

# shellcheck source=../lib/amd_devcloud_vars.sh
. "${SCRIPT_DIR}/../lib/amd_devcloud_vars.sh"
# shellcheck source=../../../lib/comm_util_funcs.sh
. "${SCRIPT_DIR}/../../../lib/comm_util_funcs.sh"

usage() {
    echo "Usage: $0 ${TARGET_USER_FLAG} USERNAME" \
        "${AUTHORIZED_KEY_FILE_FLAG} FILE [${SHOW_PLAN_ONLY_FLAG}] [-h|--help]"
}

# These root-only helpers are private to this single entrypoint. Keep them
#     co-located unless another caller or a clearer test boundary emerges.
_print_account_diagnostics() {
    local _target_user="$1"
    local _target_home="${AMD_DEVCLOUD_TARGET_HOME_PARENT}/${_target_user}"
    local _sudoers_file="${AMD_DEVCLOUD_SUDOERS_DIR}/${AMD_DEVCLOUD_SUDOERS_FILE_PREFIX}${_target_user}"

    echo "--- Existing target-account diagnostics ---" >&2
    getent passwd "${_target_user}" >&2 || :
    passwd --status "${_target_user}" >&2 || :
    id "${_target_user}" >&2 || :
    stat --format='%A %a %U:%G %n' "${_target_home}" \
        "${_target_home}/.ssh" "${_target_home}/.ssh/authorized_keys" \
        "${_sudoers_file}" >&2 2>/dev/null || :
}

# Check whether an existing account exactly matches the root-handoff baseline.
# Usage: _account_matches_baseline <target_username> <authorized_key_file>
# Returns: 0 for the exact baseline; 1 otherwise
_account_matches_baseline() (
    local _target_user="$1"
    local _authorized_key_file="$2"
    local _target_home="${AMD_DEVCLOUD_TARGET_HOME_PARENT}/${_target_user}"
    local _sudoers_file="${AMD_DEVCLOUD_SUDOERS_DIR}/${AMD_DEVCLOUD_SUDOERS_FILE_PREFIX}${_target_user}"
    local _passwd_entry
    local _passwd_name
    local _passwd_unused
    local _passwd_uid
    local _passwd_gid
    local _passwd_gecos
    local _passwd_home
    local _passwd_shell
    local _shadow_entry
    local _shadow_name
    local _shadow_password
    local _shadow_remainder
    local _expected_groups
    local _actual_groups

    _passwd_entry="$(getent passwd "${_target_user}")" || return 1
    IFS=: read -r _passwd_name _passwd_unused _passwd_uid _passwd_gid \
        _passwd_gecos _passwd_home _passwd_shell <<< "${_passwd_entry}"
    [ "${_passwd_name}" = "${_target_user}" ] || return 1
    [[ "${_passwd_uid}" =~ ^[0-9]+$ ]] || return 1
    [ "${_passwd_uid}" -ge 1000 ] && [ "${_passwd_uid}" -lt 60000 ] || return 1
    [ "${_passwd_home}" = "${_target_home}" ] || return 1
    [ "${_passwd_shell}" = "${AMD_DEVCLOUD_TARGET_LOGIN_SHELL}" ] || return 1
    [ "$(id --group --name "${_target_user}")" = "${_target_user}" ] || return 1

    [ -d "${_target_home}" ] && [ ! -L "${_target_home}" ] || return 1
    [ -d "${_target_home}/.ssh" ] && [ ! -L "${_target_home}/.ssh" ] || return 1
    [ -f "${_target_home}/.ssh/authorized_keys" ] &&
        [ ! -L "${_target_home}/.ssh/authorized_keys" ] || return 1
    [ -f "${_sudoers_file}" ] && [ ! -L "${_sudoers_file}" ] || return 1

    _shadow_entry="$(getent shadow "${_target_user}")" || return 1
    IFS=: read -r _shadow_name _shadow_password _shadow_remainder \
        <<< "${_shadow_entry}"
    [ "${_shadow_name}" = "${_target_user}" ] &&
        [ "${_shadow_password}" = "${AMD_DEVCLOUD_DISABLED_PASSWORD_FIELD}" ] ||
        return 1

    _expected_groups="$(printf '%s\n' "${_target_user}" \
        "${AMD_DEVCLOUD_REQUIRED_GROUPS[@]}" |
        LC_ALL=C sort)"
    _actual_groups="$(id --groups --name "${_target_user}" | tr ' ' '\n' |
        LC_ALL=C sort --unique)" || return 1
    [ "${_actual_groups}" = "${_expected_groups}" ] || return 1

    [ "$(stat --format='%a %U:%G' "${_target_home}")" = \
        "755 ${_target_user}:${_target_user}" ] || return 1
    [ "$(stat --format='%a %U:%G' "${_target_home}/.ssh")" = \
        "700 ${_target_user}:${_target_user}" ] || return 1
    [ "$(stat --format='%a %U:%G' \
        "${_target_home}/.ssh/authorized_keys")" = \
        "600 ${_target_user}:${_target_user}" ] || return 1
    cmp --silent "${_authorized_key_file}" \
        "${_target_home}/.ssh/authorized_keys" || return 1

    [ "$(stat --format='%a %U:%G' "${_sudoers_file}")" = \
        "440 root:root" ] || return 1
    printf '%s\n' \
        "${_target_user} ${AMD_DEVCLOUD_SUDOERS_POLICY_SUFFIX}" |
        cmp --silent - "${_sudoers_file}" || return 1
    visudo --check >/dev/null || return 1
)

# Create the exact project-owned root-to-user handoff from an absent account.
# Usage: _create_handoff_baseline <target_username> <authorized_key_file>
# Returns: 0 after creating and verifying the baseline; 1 on failure
_create_handoff_baseline() (
    local _target_user="$1"
    local _authorized_key_file="$2"
    local _target_home="${AMD_DEVCLOUD_TARGET_HOME_PARENT}/${_target_user}"
    local _sudoers_file="${AMD_DEVCLOUD_SUDOERS_DIR}/${AMD_DEVCLOUD_SUDOERS_FILE_PREFIX}${_target_user}"
    local _sudoers_temp_file=""
    local _key_temp_file=""
    local _required_group

    # Invoked indirectly by the scoped EXIT trap below.
    # shellcheck disable=SC2317
    _cleanup_handoff_temp_files() {
        local _original_status="$?"
        local _cleanup_status=0

        trap - EXIT
        if [ -n "${_key_temp_file}" ] &&
            ! rm --force -- "${_key_temp_file}"; then
            echo "ERROR: unable to remove temporary authorized-keys file!" >&2
            _cleanup_status=1
        fi
        if [ -n "${_sudoers_temp_file}" ] &&
            ! rm --force -- "${_sudoers_temp_file}"; then
            echo "ERROR: unable to remove temporary sudoers file!" >&2
            _cleanup_status=1
        fi
        if [ "${_original_status}" -ne 0 ]; then
            exit "${_original_status}"
        fi
        exit "${_cleanup_status}"
    }
    trap _cleanup_handoff_temp_files EXIT

    if [ -e "${_target_home}" ] || [ -L "${_target_home}" ] ||
        getent group "${_target_user}" >/dev/null ||
        [ -e "${_sudoers_file}" ] || [ -L "${_sudoers_file}" ]; then
        echo "ERROR: target account is absent, but a project-owned path or" >&2
        echo "    same-named group already exists; no changes were made." >&2
        return 1
    fi

    _sudoers_temp_file="$(mktemp \
        "${AMD_DEVCLOUD_SUDOERS_DIR}/.${AMD_DEVCLOUD_SUDOERS_FILE_PREFIX}${_target_user}.XXXXXX")" || {
        echo "ERROR: unable to create temporary sudoers file!" >&2
        return 1
    }
    if ! printf '%s\n' \
        "${_target_user} ${AMD_DEVCLOUD_SUDOERS_POLICY_SUFFIX}" \
        > "${_sudoers_temp_file}" ||
        ! chown root:root "${_sudoers_temp_file}" ||
        ! chmod 0440 "${_sudoers_temp_file}"; then
        echo "ERROR: unable to prepare temporary sudoers policy!" >&2
        return 1
    fi
    if ! visudo --check --file="${_sudoers_temp_file}" >/dev/null; then
        echo "ERROR: generated sudoers policy failed validation; no account" >&2
        echo "    or group changes were made." >&2
        return 1
    fi

    for _required_group in "${AMD_DEVCLOUD_REQUIRED_GROUPS[@]}"; do
        if ! getent group "${_required_group}" >/dev/null; then
            echo "Creating missing required system group '${_required_group}'..."
            if ! groupadd --system "${_required_group}"; then
                echo "ERROR: unable to create group '${_required_group}'!" >&2
                echo "WARNING: earlier required groups may have been created;" >&2
                echo "    no automatic rollback was attempted." >&2
                return 1
            fi
        fi
    done

    echo "Creating password-disabled ordinary user '${_target_user}'..."
    if ! useradd --create-home --shell "${AMD_DEVCLOUD_TARGET_LOGIN_SHELL}" \
        --user-group \
        --password "${AMD_DEVCLOUD_DISABLED_PASSWORD_FIELD}" \
        --groups "$(IFS=,; echo "${AMD_DEVCLOUD_REQUIRED_GROUPS[*]}")" \
        "${_target_user}"; then
        echo "ERROR: unable to create the password-disabled target account!" >&2
        echo "WARNING: the system may now contain partial handoff state;" >&2
        echo "    no automatic rollback was attempted." >&2
        return 1
    fi

    if ! install --directory --owner="${_target_user}" --group="${_target_user}" \
        --mode=0755 "${_target_home}" ||
        ! install --directory --owner="${_target_user}" --group="${_target_user}" \
            --mode=0700 "${_target_home}/.ssh"; then
        echo "ERROR: unable to set the target home or SSH directory state!" >&2
        echo "WARNING: the system now contains partial handoff state;" >&2
        echo "    no automatic rollback was attempted." >&2
        return 1
    fi
    _key_temp_file="$(mktemp "${_target_home}/.ssh/.authorized_keys.XXXXXX")" || {
        echo "ERROR: unable to create temporary authorized-keys file!" >&2
        return 1
    }
    # Hard links atomically publish same-filesystem temporary files and refuse
    #     to replace an unexpected destination created in the meantime.
    if ! install --owner="${_target_user}" --group="${_target_user}" \
        --mode=0600 "${_authorized_key_file}" "${_key_temp_file}" ||
        ! ln -- "${_key_temp_file}" "${_target_home}/.ssh/authorized_keys"; then
        echo "ERROR: unable to install the authorized-key state!" >&2
        echo "WARNING: the system now contains partial handoff state;" >&2
        echo "    no automatic rollback was attempted." >&2
        return 1
    fi
    if ! ln -- "${_sudoers_temp_file}" "${_sudoers_file}"; then
        echo "ERROR: unable to install the sudoers policy!" >&2
        echo "WARNING: the system now contains partial handoff state;" >&2
        echo "    no automatic rollback was attempted." >&2
        return 1
    fi
    if ! visudo --check >/dev/null; then
        echo "ERROR: complete sudoers policy failed validation after installation!" >&2
        echo "WARNING: the system now contains partial handoff state;" >&2
        echo "    no automatic rollback was attempted." >&2
        return 1
    fi

    if ! _account_matches_baseline "${_target_user}" "${_authorized_key_file}"; then
        echo "ERROR: root-to-user handoff sanity check failed!" >&2
        _print_account_diagnostics "${_target_user}"
        return 1
    fi

    echo "Root-to-user handoff baseline configured successfully."
    echo "IMPORTANT: keep this root session open and verify a separate SSH login"
    echo "    as '${_target_user}' before continuing with ordinary-user setup."
)

# BEGIN "MAIN"
TARGET_USER=""
AUTHORIZED_KEY_FILE=""

while [ "$#" -gt 0 ]; do
    case $1 in
        "${TARGET_USER_FLAG}")
            [ "$#" -ge 2 ] || {
                echo "ERROR: ${TARGET_USER_FLAG} requires a value!" >&2
                usage >&2
                exit 1
            }
            [ -z "${TARGET_USER}" ] || {
                echo "ERROR: ${TARGET_USER_FLAG} may be specified only once!" >&2
                exit 1
            }
            TARGET_USER="$2"
            shift 2
            ;;
        "${AUTHORIZED_KEY_FILE_FLAG}")
            [ "$#" -ge 2 ] || {
                echo "ERROR: ${AUTHORIZED_KEY_FILE_FLAG} requires a value!" >&2
                usage >&2
                exit 1
            }
            [ -z "${AUTHORIZED_KEY_FILE}" ] || {
                echo "ERROR: ${AUTHORIZED_KEY_FILE_FLAG} may be specified only once!" >&2
                exit 1
            }
            AUTHORIZED_KEY_FILE="$2"
            shift 2
            ;;
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

if [ -z "${TARGET_USER}" ] || [ -z "${AUTHORIZED_KEY_FILE}" ]; then
    echo "ERROR: ${TARGET_USER_FLAG} and ${AUTHORIZED_KEY_FILE_FLAG} are required!" >&2
    usage >&2
    exit 1
fi

if ! (export LC_ALL=C; [[ "${TARGET_USER}" =~ ${TARGET_USERNAME_REGEX} ]]) ||
    [ "${TARGET_USER}" = "root" ]; then
    echo "ERROR: target username must contain 1-32 lowercase ASCII letters," >&2
    echo "    digits, internal '_' or '-', must start with a letter and end" >&2
    echo "    with a letter or digit, and must not be 'root'." >&2
    exit 1
fi

if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
    echo "[PLAN ONLY] Would require a root invocation on" \
        "${AMD_DEVCLOUD_EXPECTED_DISTRO_NAME}" \
        "${AMD_DEVCLOUD_EXPECTED_DISTRO_VERSION}."
    echo "[PLAN ONLY] Would validate the authorized-key input and existing"
    echo "[PLAN ONLY]     sudoers policy without displaying key material."
    echo "[PLAN ONLY] Would recognize the exact handoff baseline for" \
        "'${TARGET_USER}', or create it only from absent account state."
    echo "[PLAN ONLY] No account, group, SSH-key, or sudoers changes were made."
    exit 0
fi

if [ "${EUID}" -ne 0 ]; then
    echo "ERROR: AMD DevCloud root bootstrap must run as root!" >&2
    exit 1
fi

for _required_command in cat cmp getent grep groupadd id install ln mktemp \
    passwd ssh-keygen stat useradd visudo; do
    command -v "${_required_command}" >/dev/null 2>&1 || {
        echo "ERROR: required command '${_required_command}' is unavailable!" >&2
        exit 1
    }
done

if ! os_release_matches_expected /etc/os-release \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_ID}" \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_VERSION}"; then
    echo "ERROR: AMD DevCloud root bootstrap requires" \
        "${AMD_DEVCLOUD_EXPECTED_DISTRO_NAME}" \
        "${AMD_DEVCLOUD_EXPECTED_DISTRO_VERSION}." >&2
    echo "--- Collected '/etc/os-release' contents ---" >&2
    if [ -r /etc/os-release ]; then
        cat /etc/os-release >&2
    else
        echo "Unable to read '/etc/os-release'." >&2
    fi
    echo "--- No account, group, SSH-key, or sudo changes were made. ---" >&2
    exit 1
fi

if [ ! -f "${AUTHORIZED_KEY_FILE}" ] || [ ! -r "${AUTHORIZED_KEY_FILE}" ] ||
    [ ! -s "${AUTHORIZED_KEY_FILE}" ]; then
    echo "ERROR: authorized-key input must be a readable, nonempty regular file!" >&2
    exit 1
fi
if LC_ALL=C grep --extended-regexp --quiet \
    '^[[:blank:]]*-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----[[:blank:]]*$' \
    "${AUTHORIZED_KEY_FILE}"; then
    echo "ERROR: authorized-key input appears to contain private-key material!" >&2
    exit 1
fi
if ! ssh-keygen -l -f "${AUTHORIZED_KEY_FILE}" >/dev/null; then
    echo "ERROR: authorized-key input contains no key recognized by ssh-keygen!" >&2
    exit 1
fi
if ! visudo --check >/dev/null; then
    echo "ERROR: existing complete sudoers policy failed validation!" >&2
    exit 1
fi

if getent passwd "${TARGET_USER}" >/dev/null; then
    if _account_matches_baseline "${TARGET_USER}" "${AUTHORIZED_KEY_FILE}"; then
        echo "Root-to-user handoff baseline already in effect; no changes made."
        exit 0
    fi

    echo "ERROR: existing target account does not exactly match the project" >&2
    echo "    handoff baseline; no automatic repair was attempted." >&2
    _print_account_diagnostics "${TARGET_USER}"
    exit 1
fi

_create_handoff_baseline "${TARGET_USER}" "${AUTHORIZED_KEY_FILE}"
