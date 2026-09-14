#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR

usage() {
    echo "Usage: $0 [-h|--help]"
}

if [ "$#" -gt 1 ]; then
    usage >&2
    exit 1
elif [ "$#" -eq 1 ]; then
    case $1 in
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
fi

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

APT_PKGS_LISTS_PATH="$(realpath "${APT_ONLY_REQS_TXT_RELPATH}")"
readonly APT_PKGS_LISTS_PATH

print_amd_devcloud_acceptance_record /etc/os-release \
    "${DEEP_LEARN_VIRTENV_DIR}" "${APT_PKGS_LISTS_PATH}" \
    "${AMD_DEVCLOUD_ROCM_VERSIONED_ROOT}"
