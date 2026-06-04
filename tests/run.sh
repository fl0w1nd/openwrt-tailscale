#!/bin/sh
# tests/run.sh — 兼容入口（已废弃）
#
# 此文件保留以兼容旧脚本引用。
# 测试套件已完全迁移到 bats-core，请使用:
#
#   sh tests/run-bats.sh
#
# 或直接:
#
#   tests/bats/_deps/bats-core/bin/bats --recursive tests/bats/
#   bats --recursive tests/bats/      (如果系统已安装 bats)

set -eu

TESTS_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)

printf '[DEPRECATED] tests/run.sh is obsolete. Redirecting to run-bats.sh...\n' >&2

exec sh "$TESTS_DIR/run-bats.sh" "$@"
