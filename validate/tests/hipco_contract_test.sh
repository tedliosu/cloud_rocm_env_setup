#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR
REPO_ROOT="$(realpath "${SCRIPT_DIR}/../..")"
readonly REPO_ROOT

cd "${REPO_ROOT}/validate/bin"
# shellcheck source=../lib/vald_util_funcs.sh
. "../lib/vald_util_funcs.sh"

expect_warpsize_patch() {
    local _architectures="$1"

    if ! _hipco_arches_need_warpsize_32 "${_architectures}"; then
        echo "FAILED: expected warp-size patch for '${_architectures}'!" >&2
        exit 1
    fi
}

expect_no_warpsize_patch() {
    local _architectures="$1"

    if _hipco_arches_need_warpsize_32 "${_architectures}"; then
        echo "FAILED: unexpected warp-size patch for '${_architectures}'!" >&2
        exit 1
    fi
}

expect_example_success() {
    local _output="$1"

    if ! _hipco_example_reported_success "${_output}"; then
        echo "FAILED: exact hipCollections success output was rejected!" >&2
        exit 1
    fi
}

expect_example_failure() {
    local _description="$1"
    local _output="$2"

    if _hipco_example_reported_success "${_output}"; then
        echo "FAILED: ${_description} was accepted as hipCollections success!" >&2
        exit 1
    fi
}

expect_warpsize_patch "gfx1100"
expect_warpsize_patch "gfx1101"
expect_warpsize_patch "gfx942,gfx1101"
expect_warpsize_patch "gfx942;gfx1100"
expect_no_warpsize_patch "gfx942"
expect_no_warpsize_patch "gfx11010"
expect_no_warpsize_patch "prefix-gfx1101"

expect_example_success "Success! Found all values."
expect_example_success $'diagnostic\nSuccess! Found all values.\ncomplete'
expect_example_failure "substring output" "Operation was unsuccessful"
expect_example_failure "case-changed output" "SUCCESS! Found all values."
expect_example_failure "extended output" "Success! Found all values. eventually"

echo "PASSED hipCollections contract tests!"
