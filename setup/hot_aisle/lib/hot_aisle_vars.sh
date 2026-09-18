# shellcheck shell=bash
# This file is sourced by the Hot Aisle setup script; standalone analysis
#     cannot see its consumers.
# shellcheck disable=SC2034

readonly EXPECTED_DISTRO="Ubuntu"
readonly EXPECTED_DIST_VER="24.04"
readonly EXPECTED_DIST_CODENAME="noble"
readonly EXPECTED_ROCM_VER="7.2"
EXPECTED_ROCMVER_REGEX="$(printf "%s" "^${EXPECTED_ROCM_VER}.[0-9]+" | sed 's/\./\\./g')"
readonly EXPECTED_ROCMVER_REGEX
readonly FASTFETCH_PPA_FULLPATH="/etc/apt/sources.list.d/zhangsongcui3371-ubuntu-fastfetch-${EXPECTED_DIST_CODENAME}.list"
readonly FASTFETCH_PPA_URL="https://ppa.launchpadcontent.net/zhangsongcui3371/fastfetch/ubuntu/dists/${EXPECTED_DIST_CODENAME}/Release"

# The setup entry script consumes these as sourced shell values. Clear any
#     inherited export attributes so they do not leak to child processes.
export -n EXPECTED_DISTRO EXPECTED_DIST_VER EXPECTED_DIST_CODENAME
export -n EXPECTED_ROCM_VER EXPECTED_ROCMVER_REGEX FASTFETCH_PPA_FULLPATH
export -n FASTFETCH_PPA_URL
