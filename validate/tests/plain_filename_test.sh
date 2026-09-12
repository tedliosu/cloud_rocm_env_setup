#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
readonly REPO_ROOT

cd "${REPO_ROOT}/validate/bin"
# shellcheck source=../lib/vald_util_funcs.sh
. "../lib/vald_util_funcs.sh"

expect_plain_filename() {
    local _filename="$1"

    if ! is_plain_filename "${_filename}"; then
        echo "FAILED: safe filename '${_filename}' was rejected!" >&2
        exit 1
    fi
}

expect_rejection() {
    local _description="$1"
    local _filename="$2"

    if is_plain_filename "${_filename}"; then
        echo "FAILED: ${_description} was accepted as a plain filename!" >&2
        exit 1
    fi
}

expect_plain_filename "flux1-dev-fp8.safetensors"
expect_plain_filename "checkpoint with spaces.safetensors"
expect_rejection "empty input" ""
expect_rejection "current-directory component" "."
expect_rejection "parent-directory component" ".."
expect_rejection "relative path" "../outside-model"
expect_rejection "nested path" "models/checkpoint.safetensors"
expect_rejection "multiple selected values" $'first.safetensors\nsecond.safetensors'

if is_plain_filename; then
    echo "FAILED: missing filename argument was accepted!" >&2
    exit 1
fi
if is_plain_filename first second; then
    echo "FAILED: multiple filename arguments were accepted!" >&2
    exit 1
fi

echo "PASSED plain filename validation tests!"
