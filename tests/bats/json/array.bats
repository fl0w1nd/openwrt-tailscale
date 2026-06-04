#!/usr/bin/env bats
# tests/bats/json/array.bats

load ../_lib/load

setup() {
    setup_test_env
    source_lib json
}

teardown() {
    teardown_test_env
}

@test "json_array_from_lines: builds array from multiple lines" {
    result=$(printf 'a\nb\nc\n' | json_array_from_lines)
    assert_equal '["a","b","c"]' "${result}"
}

@test "json_array_from_lines: returns empty array for empty input" {
    result=$(printf '' | json_array_from_lines)
    assert_equal '[]' "${result}"
}

@test "json_array_from_lines: handles single element" {
    result=$(printf 'single\n' | json_array_from_lines)
    assert_equal '["single"]' "${result}"
}
