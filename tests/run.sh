#!/bin/sh
# tests/run.sh — Test dispatcher
#
# Sources helpers and per-module test files, then runs all (or selected) tests.
# Usage:
#   sh tests/run.sh                      # run all tests
#   TEST_MODULE=version sh tests/run.sh  # run only version tests
#   TEST_MODULE="version json" sh tests/run.sh  # run version + json tests

set -eu

TESTS_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)

. "$TESTS_DIR/helpers.sh"

AVAILABLE_MODULES="common version download firewall deploy selfupdate json rpcd"
MODULES=$AVAILABLE_MODULES

if [ -n "${TEST_MODULE:-}" ]; then
    MODULES="$TEST_MODULE"
fi

for module in $MODULES; do
    module_file="$TESTS_DIR/${module}.sh"
    if [ ! -f "$module_file" ]; then
        printf 'ERROR: module file not found: %s\n' "$module_file" >&2
        exit 1
    fi
    . "$module_file"
    runner="run_${module}_tests"
    if ! command -v "$runner" >/dev/null 2>&1; then
        printf 'ERROR: test runner not found: %s\n' "$runner" >&2
        exit 1
    fi
    "$runner"
done

printf '1..%s\n' "$TEST_INDEX"
