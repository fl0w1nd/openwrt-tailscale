#!/usr/bin/env bats
# tests/bats/json/escape.bats
# Migrated from tests/json.sh: test_json_escape_special_chars, test_json_array_from_lines

load ../_lib/load

setup() {
    setup_test_env
    source_lib json
}

teardown() {
    teardown_test_env
}

@test "json_escape: escapes double quotes" {
    result=$(json_escape 'hello "world"')
    assert_equal 'hello \"world\"' "${result}"
}

@test "json_escape: escapes backslashes" {
    result=$(json_escape 'back\slash')
    assert_equal 'back\\slash' "${result}"
}

@test "json_escape: passes through plain strings unchanged" {
    result=$(json_escape 'no special')
    assert_equal 'no special' "${result}"
}

@test "json_escape: handles empty string" {
    result=$(json_escape '')
    assert_equal '' "${result}"
}

@test "json_escape: escapes newlines" {
    result=$(json_escape "$(printf 'line1\nline2')")
    assert_equal 'line1\nline2' "${result}"
}
