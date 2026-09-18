#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/..")"
readonly REPO_ROOT

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "ERROR: shellcheck is required to run repository shell analysis." >&2
    exit 1
fi

mapfile -t SHELL_FILES < <(
    git -C "${REPO_ROOT}" ls-files --cached --others --exclude-standard \
        -- '*.sh' | sort
)
readonly SHELL_FILES

if [ "${#SHELL_FILES[@]}" -eq 0 ]; then
    echo "ERROR: no shell files were found for ShellCheck." >&2
    exit 1
fi

cd "${REPO_ROOT}"
shellcheck --external-sources --source-path=SCRIPTDIR "${SHELL_FILES[@]}"

echo "PASSED ShellCheck for all ${#SHELL_FILES[@]} repository shell files!"
