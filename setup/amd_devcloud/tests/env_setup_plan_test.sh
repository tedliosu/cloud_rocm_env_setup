#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
SETUP_SCRIPT="$(realpath "${SCRIPT_DIR}/../bin/amd_devcloud_env_setup.sh")"
readonly SETUP_SCRIPT
TEST_TMP_DIR="$(mktemp --directory)"
readonly TEST_TMP_DIR
TEST_BIN_DIR="${TEST_TMP_DIR}/bin"
readonly TEST_BIN_DIR
STATE_TRACKER_PATH="${TEST_TMP_DIR}/state_trackers"
readonly STATE_TRACKER_PATH
TEST_REALPATH_COMMAND="$(command -v realpath)"
export TEST_REALPATH_COMMAND
export TEST_STATE_TRACKER_PATH="${STATE_TRACKER_PATH}"

cleanup() {
    rm --recursive --force "${TEST_TMP_DIR}"
}
trap cleanup EXIT

mkdir "${TEST_BIN_DIR}"

# Keep plan assertions independent of ignored milestones in a live checkout.
# Single quotes preserve these expressions for the generated command double.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'if [ "$#" -eq 1 ] && [ "$1" = "../state_trackers" ]; then' \
    '    printf "%s\n" "${TEST_STATE_TRACKER_PATH}"' \
    '    exit 0' \
    'fi' \
    'exec "${TEST_REALPATH_COMMAND}" "$@"' \
    > "${TEST_BIN_DIR}/realpath"
chmod +x "${TEST_BIN_DIR}/realpath"
export PATH="${TEST_BIN_DIR}:${PATH}"

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
    "would run stage install_amd_devcloud_rocm_userland" \
    "Would ensure the exact versioned ROCm PATH profile block" \
    "Would report versioned PATH, ROCM_HOME, and LD_LIBRARY_PATH use" \
    "Would stop after ROCm userland before the common minimum baseline"; do
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
