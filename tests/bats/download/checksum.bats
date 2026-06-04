#!/usr/bin/env bats
# tests/bats/download/checksum.bats
# Migrated from tests/download.sh: test_compute_sha256, test_verify_checksum_*,
#   test_get_official_checksum_format, test_get_small_checksum_parse*

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "compute_sha256 returns correct hash" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

echo 'hello world' > '${TEST_DIR}/testfile'
expected=\$(sha256sum '${TEST_DIR}/testfile' | awk '{print \$1}')
actual=\$(compute_sha256 '${TEST_DIR}/testfile')
[ \"\$expected\" = \"\$actual\" ] || { echo \"hash mismatch: expected=\$expected actual=\$actual\"; exit 1; }
"
    assert_success
}

@test "verify_checksum accepts matching hash" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

echo 'test data' > '${TEST_DIR}/testfile'
hash=\$(compute_sha256 '${TEST_DIR}/testfile')
verify_checksum '${TEST_DIR}/testfile' \"\$hash\"
"
    assert_success
}

@test "verify_checksum rejects mismatched hash" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

echo 'test data' > '${TEST_DIR}/testfile'
bad_hash='0000000000000000000000000000000000000000000000000000000000000000'
if verify_checksum '${TEST_DIR}/testfile' \"\$bad_hash\" 2>/dev/null; then
    echo 'should have failed'
    exit 1
fi
"
    assert_success
}

@test "verify_checksum skips gracefully when no tools available" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

compute_sha256() { return 1; }

echo 'test data' > '${TEST_DIR}/testfile'
verify_checksum '${TEST_DIR}/testfile' 'anything' 2>/dev/null
"
    assert_success
}

@test "get_official_checksum validates and returns 64-char hex hash" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

wget() { echo 'a1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc'; }
result=\$(get_official_checksum 'http://example.com/test.tgz')
[ \"\$result\" = 'a1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc' ] || { echo 'valid hash rejected'; exit 1; }

wget() { echo 'abc123'; }
if get_official_checksum 'http://example.com/test.tgz' 2>/dev/null; then
    echo 'short hash accepted'
    exit 1
fi

wget() { echo 'g1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc'; }
if get_official_checksum 'http://example.com/test.tgz' 2>/dev/null; then
    echo 'non-hex hash accepted'
    exit 1
fi
"
    assert_success
}

@test "get_small_checksum parses pretty-printed GitHub API JSON" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
SMALL_RELEASES_API='file://'

cat > '${TEST_DIR}/github-api.json' <<'APIJSON'
{
  \"tag_name\": \"v1.96.4\",
  \"assets\": [
    {
      \"name\": \"tailscale-small_1.96.4_amd64.tgz\",
      \"size\": 10484696,
      \"digest\": \"sha256:be3ee2b34c609b77e51c04cc1044054f7d7153749df0d25a24d4b54456623395\"
    },
    {
      \"name\": \"tailscale-small_1.96.4_arm.tgz\",
      \"size\": 7500000,
      \"digest\": \"sha256:3b480915d85bc9990f97e3babecccbd45b09b32ab09577e4eca76ef435aae10e\"
    }
  ]
}
APIJSON

wget() { cat '${TEST_DIR}/github-api.json'; }

result=\$(get_small_checksum '1.96.4' 'tailscale-small_1.96.4_amd64.tgz')
[ \"\$result\" = 'be3ee2b34c609b77e51c04cc1044054f7d7153749df0d25a24d4b54456623395' ] || { echo \"amd64 hash mismatch: \$result\"; exit 1; }

result=\$(get_small_checksum '1.96.4' 'tailscale-small_1.96.4_arm.tgz')
[ \"\$result\" = '3b480915d85bc9990f97e3babecccbd45b09b32ab09577e4eca76ef435aae10e' ] || { echo \"arm hash mismatch: \$result\"; exit 1; }

if get_small_checksum '1.96.4' 'tailscale-small_1.96.4_mips.tgz' 2>/dev/null; then
    echo 'non-existent arch should fail'
    exit 1
fi
"
    assert_success
}

@test "get_small_checksum parses compact (single-line) GitHub API JSON (regression #14)" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
SMALL_RELEASES_API='file://'

cat > '${TEST_DIR}/github-api.json' <<'APIJSON'
{\"tag_name\":\"v1.98.3\",\"assets\":[{\"name\":\"tailscale-small_1.98.3_amd64.tgz\",\"size\":10654681,\"digest\":\"sha256:e024c878c085ac6b54c6e3f3cf446184a3b6475a147657de83345d458ed1b02c\"},{\"name\":\"tailscale-small_1.98.3_arm.tgz\",\"size\":7945778,\"digest\":\"sha256:0fa2d7628a8ea15a4470df5d963a125f9658532cf91741e9e40204f73bfefcca\"},{\"name\":\"tailscale-small_1.98.3_mips.tgz\",\"size\":7744584,\"digest\":\"sha256:7c12d950cfc3c1813de2d2e523437c53683398e28c8513e2d2578606a18674c2\"},{\"name\":\"tailscale-small_1.98.3_mipsle.tgz\",\"size\":7914233,\"digest\":\"sha256:338d4794c3d57038da62eaefc6ed9f59489e56e8424ec3c68c27bad64e6f90c6\"}]}
APIJSON

wget() { cat '${TEST_DIR}/github-api.json'; }

# big-endian mips (regression: used to return mipsle hash)
result=\$(get_small_checksum '1.98.3' 'tailscale-small_1.98.3_mips.tgz')
[ \"\$result\" = '7c12d950cfc3c1813de2d2e523437c53683398e28c8513e2d2578606a18674c2' ] || { echo \"mips hash mismatch: \$result\"; exit 1; }

result=\$(get_small_checksum '1.98.3' 'tailscale-small_1.98.3_mipsle.tgz')
[ \"\$result\" = '338d4794c3d57038da62eaefc6ed9f59489e56e8424ec3c68c27bad64e6f90c6' ] || { echo \"mipsle hash mismatch: \$result\"; exit 1; }

result=\$(get_small_checksum '1.98.3' 'tailscale-small_1.98.3_arm.tgz')
[ \"\$result\" = '0fa2d7628a8ea15a4470df5d963a125f9658532cf91741e9e40204f73bfefcca' ] || { echo \"arm hash mismatch: \$result\"; exit 1; }

if get_small_checksum '1.98.3' 'tailscale-small_1.98.3_mips64.tgz' 2>/dev/null; then
    echo 'missing arch should fail'
    exit 1
fi
"
    assert_success
}
