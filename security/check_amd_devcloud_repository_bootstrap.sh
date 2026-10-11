#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/..")"
readonly REPO_ROOT
readonly TRUSTED_ORIGIN="https://repo.radeon.com"

# shellcheck source=../setup/amd_devcloud/lib/amd_devcloud_vars.sh
. "${REPO_ROOT}/setup/amd_devcloud/lib/amd_devcloud_vars.sh"

for _required_command in curl dpkg-deb mktemp rm sha256sum; do
    if ! command -v "${_required_command}" >/dev/null 2>&1; then
        echo "ERROR: provenance check requires '${_required_command}'!" >&2
        exit 1
    fi
done

case ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL} in
    "${TRUSTED_ORIGIN}/"*) ;;
    *)
        echo "ERROR: AMD repository-bootstrap URL is outside the reviewed origin!" >&2
        exit 1
        ;;
esac
case ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL} in
    */"${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_FILENAME}") ;;
    *)
        echo "ERROR: AMD repository-bootstrap URL and filename disagree!" >&2
        exit 1
        ;;
esac

_temp_dir="$(mktemp --directory --tmpdir amd-repository-provenance.XXXXXX)"
readonly _temp_dir
_package_path="${_temp_dir}/${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_FILENAME}"
readonly _package_path
trap 'rm --recursive --force -- "${_temp_dir}"' EXIT

if ! _effective_url="$(curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' \
    --output "${_package_path}" --write-out '%{url_effective}' \
    "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}")"; then
    echo "ERROR: unable to fetch the reviewed AMD repository bootstrap!" >&2
    exit 1
fi
if [ "${_effective_url}" != "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}" ]; then
    echo "ERROR: AMD repository-bootstrap download redirected unexpectedly!" >&2
    echo "    Expected: ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}" >&2
    echo "    Effective: ${_effective_url}" >&2
    exit 1
fi
if [ ! -s "${_package_path}" ]; then
    echo "ERROR: AMD repository-bootstrap download is empty!" >&2
    exit 1
fi
if ! printf '%s  %s\n' "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_SHA256}" \
    "${_package_path}" | sha256sum --check --status; then
    echo "ERROR: AMD repository-bootstrap SHA-256 drift detected!" >&2
    exit 1
fi
if ! _package_version="$(dpkg-deb --field "${_package_path}" Version)"; then
    echo "ERROR: unable to inspect AMD repository-bootstrap metadata!" >&2
    exit 1
fi
if [ "${_package_version}" != \
    "${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}" ]; then
    echo "ERROR: AMD repository-bootstrap package-version drift detected!" >&2
    exit 1
fi

echo "AMD DevCloud repository-bootstrap provenance receipt still matches."
echo "Validated URL: ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_URL}"
echo "Validated SHA-256: ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_SHA256}"
echo "Validated package version: ${AMD_DEVCLOUD_REPOSITORY_BOOTSTRAP_PACKAGE_VERSION}"
