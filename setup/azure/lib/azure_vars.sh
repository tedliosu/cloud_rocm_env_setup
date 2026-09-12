
export EXPECTED_DISTRO="Ubuntu"
export EXPECTED_DIST_VER="24.04"
export EXPECTED_DIST_CODENAME="noble"
export EXPECTED_ROCM_VER="7.2"
EXPECTED_ROCMVER_REGEX="$(printf "%s" "^${EXPECTED_ROCM_VER}.[0-9]+" | sed 's/\./\\./g')"
export EXPECTED_ROCMVER_REGEX
export FASTFETCH_PIN_VER="2.62.1"
export FASTFETCH_DEB_FILENAME="fastfetch-linux-amd64.deb"
