#!/bin/sh
# tests/run-bats.sh — bats 测试套件入口
#
# Usage:
#   sh tests/run-bats.sh                          # 跑所有项目 bats 测试
#   sh tests/run-bats.sh tests/bats/json          # 跑指定目录/文件
#   make test-e2e                                 # 跑 e2e 标记的测试
#   sh tests/run-bats.sh -- --jobs 4              # 透传额外 bats 参数
#
# 默认仅运行 tests/bats 下的业务测试目录（common/version/download/...），
# 主动跳过 `_deps`、`_lib`、`_fixtures` 这些以下划线开头的辅助目录，
# 防止把第三方 submodule 自带的 fixture 测试也卷进来跑。
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
BATS_BIN="$REPO_ROOT/tests/bats/_deps/bats-core/bin/bats"

if [ -z "${SHELL_UNDER_TEST:-}" ] && [ -n "${TEST_SHELL:-}" ]; then
    export SHELL_UNDER_TEST="$TEST_SHELL"
fi

if [ ! -x "$BATS_BIN" ]; then
    if command -v bats >/dev/null 2>&1; then
        BATS_BIN=$(command -v bats)
    else
        printf 'ERROR: bats not found.\n' >&2
        printf '  Initialise the submodules first:\n' >&2
        printf '    git submodule update --init --recursive\n' >&2
        printf '  Or install bats system-wide (apt-get install bats / brew install bats-core).\n' >&2
        exit 1
    fi
fi

if [ "$#" -eq 0 ]; then
    # Collect every direct subdirectory of tests/bats that isn't a helper
    # bucket (_deps/_lib/_fixtures) or a network-dependent smoke suite.
    # bats `--recursive` will then descend into each business module
    # without touching vendored fixtures or external API endpoints.
    BATS_DIR="$REPO_ROOT/tests/bats"
    set --
    for dir in "$BATS_DIR"/*/; do
        [ -d "$dir" ] || continue
        case "${dir##*/tests/bats/}" in
            _*)       continue ;;   # helper buckets
            smoke)    continue ;;   # network-dependent; run separately in CI
        esac
        set -- "$@" "$dir"
    done
    if [ "$#" -eq 0 ]; then
        printf 'ERROR: no bats test directories found under %s\n' "$BATS_DIR" >&2
        exit 1
    fi
fi

exec "$BATS_BIN" --recursive "$@"
