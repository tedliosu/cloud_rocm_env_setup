
export EXPECTED_DISTRO="Ubuntu"
export EXPECTED_DIST_VER="24.04"
export EXPECTED_DIST_CODENAME="noble"
export EXPECTED_ROCM_VER="7.2"
EXPECTED_ROCMVER_REGEX="$(printf "%s" "^${EXPECTED_ROCM_VER}.[0-9]+" | sed 's/\./\\./g')"
export EXPECTED_ROCMVER_REGEX
export FASTFETCH_PPA_FULLPATH="/etc/apt/sources.list.d/zhangsongcui3371-ubuntu-fastfetch-${EXPECTED_DIST_CODENAME}.list"
export FASTFETCH_PPA_URL="https://ppa.launchpadcontent.net/zhangsongcui3371/fastfetch/ubuntu/dists/${EXPECTED_DIST_CODENAME}/Release"

