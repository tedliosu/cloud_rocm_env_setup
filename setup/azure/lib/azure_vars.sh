# shellcheck shell=bash
# This file is sourced by the Azure setup script; standalone analysis cannot
#     see its consumers.
# shellcheck disable=SC2034

readonly EXPECTED_DISTRO="Ubuntu"
readonly EXPECTED_DIST_VER="24.04"
readonly EXPECTED_DIST_CODENAME="noble"
readonly EXPECTED_ROCM_VER="7.2"
EXPECTED_ROCMVER_REGEX="$(printf "%s" "^${EXPECTED_ROCM_VER}.[0-9]+" | sed 's/\./\\./g')"
readonly EXPECTED_ROCMVER_REGEX
readonly FASTFETCH_PIN_VER="2.62.1"
readonly FASTFETCH_DEB_FILENAME="fastfetch-linux-amd64.deb"

# The setup entry script consumes these as sourced shell values. Clear any
#     inherited export attributes so they do not leak to child processes.
export -n EXPECTED_DISTRO EXPECTED_DIST_VER EXPECTED_DIST_CODENAME
export -n EXPECTED_ROCM_VER EXPECTED_ROCMVER_REGEX FASTFETCH_PIN_VER
export -n FASTFETCH_DEB_FILENAME
