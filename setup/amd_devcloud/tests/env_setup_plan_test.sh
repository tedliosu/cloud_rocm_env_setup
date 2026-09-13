#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
SETUP_SCRIPT="$(realpath "${SCRIPT_DIR}/../bin/amd_devcloud_env_setup.sh")"
readonly SETUP_SCRIPT
STATE_TRACKER_PATH="$(realpath "${SCRIPT_DIR}/../state_trackers")"
readonly STATE_TRACKER_PATH

_state_tracker_existed=0
if [ -e "${STATE_TRACKER_PATH}" ] || [ -L "${STATE_TRACKER_PATH}" ]; then
    _state_tracker_existed=1
fi

_plan_output="$("${SETUP_SCRIPT}" --show-plan-only)"

_previous_line_number=0
for _expected_line in \
    "Would verify the ordinary-user identity" \
    "Would ensure that current environment is Ubuntu 24.04" \
    "Would require a finite accepted AMD DevCloud stack state" \
    "Would inspect current UFW state and apply the project" \
    "would run stage apt_get_sys_update" \
    "would run stage ensure_tmux" \
    "Would record reboot phase amd_devcloud_system_upgrade_reboot" \
    "would run stage install_amd_devcloud_repository_bootstrap" \
    "would run stage install_amd_devcloud_driver" \
    "Would record reboot phase amd_devcloud_driver_reboot" \
    "Would verify the running-kernel AMDGPU DKMS state" \
    "Would stop at the driver acceptance checkpoint before ROCm userland"; do
    if ! _line_match="$(grep --fixed-strings --line-number --max-count=1 \
        "${_expected_line}" <<< "${_plan_output}")"; then
        echo "FAILED: DevCloud setup plan omitted '${_expected_line}'!" >&2
        exit 1
    fi
    _line_number="${_line_match%%:*}"
    if [ "${_line_number}" -le "${_previous_line_number}" ]; then
        echo "FAILED: DevCloud setup plan checks are out of safety order!" >&2
        exit 1
    fi
    _previous_line_number="${_line_number}"
done

if grep --invert-match --extended-regexp --quiet '^\[PLAN ONLY\]' \
    <<< "${_plan_output}"; then
    echo "FAILED: DevCloud setup plan included unlabeled output!" >&2
    exit 1
fi
if grep --fixed-strings --quiet "preflight passed" <<< "${_plan_output}"; then
    echo "FAILED: DevCloud setup plan claimed that skipped checks passed!" >&2
    exit 1
fi

if [ "${_state_tracker_existed}" -eq 0 ] &&
    { [ -e "${STATE_TRACKER_PATH}" ] || [ -L "${STATE_TRACKER_PATH}" ]; }; then
    echo "FAILED: DevCloud setup plan created the state-trackers path!" >&2
    exit 1
fi

echo "PASSED AMD DevCloud setup plan tests!"
