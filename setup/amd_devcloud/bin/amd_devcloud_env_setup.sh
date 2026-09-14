#!/bin/bash

set -euo pipefail

readonly SHOW_PLAN_ONLY_FLAG="--show-plan-only"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR

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

OLD_CWDIR="$(pwd -P)" || {
    echo "ERROR: unable to resolve the initial working directory!" >&2
    exit 1
}
readonly OLD_CWDIR
cd "${SCRIPT_DIR}" || {
    echo "ERROR: unable to enter the AMD DevCloud script directory!" >&2
    exit 1
}

# shellcheck source=../lib/amd_devcloud_vars.sh
. "../lib/amd_devcloud_vars.sh"
# shellcheck source=../lib/amd_devcloud_funcs.sh
. "../lib/amd_devcloud_funcs.sh"
# shellcheck source=../../common/lib/shared_vars.sh
. "../../common/lib/shared_vars.sh"
# shellcheck source=../../common/lib/util_funcs.sh
. "../../common/lib/util_funcs.sh"

MILESTONES_DIR="$(realpath "${MILESTONES_DIR_RELPATH}")"
readonly MILESTONES_DIR
APT_PKGS_LISTS_PATH="$(realpath "${APT_ONLY_REQS_TXT_RELPATH}")"
readonly APT_PKGS_LISTS_PATH

# BEGIN "MAIN"
if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
    "${SCRIPT_DIR}/amd_devcloud_handoff_preflight.sh" "${SHOW_PLAN_ONLY_FLAG}"
else
    "${SCRIPT_DIR}/amd_devcloud_handoff_preflight.sh"
fi
ensure_basic_os_env_sanity_dont_wrap \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_NAME}" \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_VERSION}"
check_amd_devcloud_setup_admission_dont_wrap "${MILESTONES_DIR}"
if [ "${SHOW_PLAN_ONLY:-0}" -ne 1 ]; then
    mkdir --parents "${MILESTONES_DIR}"
fi
check_n_apply_ufw_base_or_warn_dont_wrap
run_stage "${MILESTONES_DIR}" "${AMD_DEVCLOUD_SYSTEM_UPGRADE_STAGE_NAME}"
run_stage "${MILESTONES_DIR}" "${AMD_DEVCLOUD_TMUX_STAGE_NAME}"
reboot_with_ack_dont_wrap \
    "${MILESTONES_DIR}" "${AMD_DEVCLOUD_SYSTEM_UPGRADE_REBOOT_NAME}"
run_stage "${MILESTONES_DIR}" \
    "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_STAGE_NAME}"
run_stage "${MILESTONES_DIR}" "${AMD_DEVCLOUD_DRIVER_STAGE_NAME}"
reboot_with_ack_dont_wrap \
    "${MILESTONES_DIR}" "${AMD_DEVCLOUD_DRIVER_REBOOT_NAME}"
# shellcheck disable=SC2119 # The verifier deliberately accepts no arguments.
verify_amd_devcloud_post_driver_state_dont_wrap
run_stage "${MILESTONES_DIR}" "${AMD_DEVCLOUD_ROCM_USERLAND_STAGE_NAME}"
ensure_amd_devcloud_rocm_path_profile_dont_wrap "${CURR_HOME_DIR}"
# shellcheck disable=SC2119 # The reporter deliberately accepts no arguments.
print_amd_devcloud_rocm_paths_dont_wrap
run_stage "${MILESTONES_DIR}" ensure_pinned_cmake \
    "${AMD_DEVCLOUD_EXPECTED_DISTRO_CODENAME}" "${CMAKE_APT_PIN_VER}"
run_stage "${MILESTONES_DIR}" ensure_apt_with_custom_conf \
    "${CURR_HOME_DIR}" "${APT_PKGS_LISTS_PATH}"

if [ "${SHOW_PLAN_ONLY:-0}" -eq 1 ]; then
    echo "[PLAN ONLY] Would stop after common system prerequisites before the baseline Python environment."
else
    echo "Stopping after common system prerequisites before the baseline Python environment."
fi

cd "${OLD_CWDIR}" || {
    echo "ERROR: unable to return to the initial working directory!" >&2
    exit 1
}
