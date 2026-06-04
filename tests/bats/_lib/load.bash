#!/usr/bin/env bash
# tests/bats/_lib/load.bash — Unified helper loader
#
# Usage in .bats files:
#   load ../_lib/load        (from tests/bats/<module>/*.bats)
#   load ../../_lib/load     (adjust depth as needed)
#
# This file is auto-discovered by bats via its "load" builtin.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DEPS_DIR="$(cd "${_LIB_DIR}/../_deps" && pwd)"

# Load bats helper libraries
load "${_DEPS_DIR}/bats-support/load"
load "${_DEPS_DIR}/bats-assert/load"
load "${_DEPS_DIR}/bats-file/load"

# Load project helpers
# shellcheck source=setup.bash
source "${_LIB_DIR}/setup.bash"
# shellcheck source=mocks.bash
source "${_LIB_DIR}/mocks.bash"
# shellcheck source=run_in_sh.bash
source "${_LIB_DIR}/run_in_sh.bash"
