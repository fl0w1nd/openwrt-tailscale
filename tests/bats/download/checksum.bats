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

@test "verify_checksum rejects missing checksum tools by default" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

compute_sha256() { return 1; }

echo 'test data' > '${TEST_DIR}/testfile'
if verify_checksum '${TEST_DIR}/testfile' 'anything' 2>/dev/null; then
    echo 'missing checksum tools accepted'
    exit 1
fi
"
    assert_success
}

@test "verify_checksum honors explicit emergency override" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

compute_sha256() { return 1; }

TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD=1
export TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD

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

@test "download_tailscale_official requires checksum metadata by default" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
DOWNLOAD_BASE='https://example.test/stable'

wget() {
    case \"\$1\" in
        -qO-) return 1 ;;
        --help) return 0 ;;
        *) echo \"download should not run: \$*\" >&2; return 1 ;;
    esac
}

if download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target' 2>/dev/null; then
    echo 'download accepted missing checksum metadata'
    exit 1
fi
"
    assert_success
}

@test "download_tailscale_official rejects checksum mismatch" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
DOWNLOAD_BASE='https://example.test/stable'

archive_root='${TEST_DIR}/archive-root'
mkdir -p \"\$archive_root/tailscale_1.2.3_amd64\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscale\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscaled\"

wget() {
    case \"\$1\" in
        -qO-)
            printf '%064d\n' 0
            return 0
            ;;
        --help)
            return 0
            ;;
        -q)
            tar czf \"\$3\" -C \"\$archive_root\" tailscale_1.2.3_amd64
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

if download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target' 2>/dev/null; then
    echo 'download accepted mismatched checksum'
    exit 1
fi
"
    assert_success
}

@test "download_tailscale_official allows explicit emergency checksum override" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
DOWNLOAD_BASE='https://example.test/stable'
TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD=1
export TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD

archive_root='${TEST_DIR}/archive-root'
mkdir -p \"\$archive_root/tailscale_1.2.3_amd64\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscale\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscaled\"

wget() {
    case \"\$1\" in
        -qO-) return 1 ;;
        --help) return 0 ;;
        -q)
            tar czf \"\$3\" -C \"\$archive_root\" tailscale_1.2.3_amd64
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target'
[ -f '${TEST_DIR}/target/tailscale' ] || { echo 'tailscale missing'; exit 1; }
[ -f '${TEST_DIR}/target/tailscaled' ] || { echo 'tailscaled missing'; exit 1; }
"
    assert_success
}

@test "download_tailscale_official rejects path traversal archive members" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
DOWNLOAD_BASE='https://example.test/stable'
TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD=1
export TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD

archive_root='${TEST_DIR}/traversal-root'
mkdir -p \"\$archive_root/safe\"
printf 'unsafe\n' > \"\$archive_root/evil\"
python3 - '${TEST_DIR}/traversal.tgz' <<'PY'
import io
import sys
import tarfile

data = b'unsafe\n'
info = tarfile.TarInfo('../evil')
info.size = len(data)
with tarfile.open(sys.argv[1], 'w:gz') as tar:
    tar.addfile(info, io.BytesIO(data))
PY
extraction_marker='${TEST_DIR}/extraction-called'

wget() {
    case \"\$1\" in
        -qO-) return 1 ;;
        --help) return 0 ;;
        -q)
            cp '${TEST_DIR}/traversal.tgz' \"\$3\"
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

tar() {
    case \"\$1\" in
        xzf)
            printf 'called\n' > \"\$extraction_marker\"
            return 1
            ;;
    esac
    command tar \"\$@\"
}

if download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target' 2>/dev/null; then
    echo 'download accepted unsafe archive member'
    exit 1
fi

[ ! -f \"\$extraction_marker\" ] || { echo 'unsafe archive reached extraction'; exit 1; }
"
    assert_success
}

@test "validate_tar_member_paths rejects unsafe symlink targets" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

archive_root='${TEST_DIR}/symlink-root'
mkdir -p \"\$archive_root/tailscale_1.2.3_amd64\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscale\"
ln -s /etc/shadow \"\$archive_root/tailscale_1.2.3_amd64/tailscaled\"
tar czf '${TEST_DIR}/symlink-target.tgz' -C \"\$archive_root\" tailscale_1.2.3_amd64

if validate_tar_member_paths '${TEST_DIR}/symlink-target.tgz' '${TEST_DIR}/members.list' 2>/dev/null; then
    echo 'unsafe symlink target accepted'
    exit 1
fi
"
    assert_success
}

@test "download_tailscale_official emergency override still rejects checksum mismatch" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
DOWNLOAD_BASE='https://example.test/stable'
TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD=1
export TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD

archive_root='${TEST_DIR}/archive-root'
mkdir -p \"\$archive_root/tailscale_1.2.3_amd64\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscale\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscaled\"

wget() {
    case \"\$1\" in
        -qO-)
            printf '%064d\n' 0
            return 0
            ;;
        --help)
            return 0
            ;;
        -q)
            tar czf \"\$3\" -C \"\$archive_root\" tailscale_1.2.3_amd64
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

if download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target' 2>/dev/null; then
    echo 'override accepted mismatched checksum'
    exit 1
fi
"
    assert_success
}

@test "download_tailscale_small rejects checksum mismatch" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
SMALL_DOWNLOAD_BASE='https://example.test/releases/download'

get_small_checksum() {
    printf '%064d\n' 0
}

archive_root='${TEST_DIR}/small-root'
mkdir -p \"\$archive_root/tailscale-small_1.2.3_amd64\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale-small_1.2.3_amd64/tailscale.combined\"

wget() {
    case \"\$1\" in
        --help)
            return 0
            ;;
        -q)
            tar czf \"\$3\" -C \"\$archive_root\" tailscale-small_1.2.3_amd64
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

if download_tailscale_small '1.2.3' 'amd64' '${TEST_DIR}/target' 2>/dev/null; then
    echo 'small download accepted mismatched checksum'
    exit 1
fi
"
    assert_success
}

@test "download_tailscale_small rejects path traversal archive members before extraction" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
SMALL_DOWNLOAD_BASE='https://example.test/releases/download'
TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD=1
export TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD

archive_root='${TEST_DIR}/small-traversal-root'
mkdir -p \"\$archive_root/safe\"
printf 'unsafe\n' > \"\$archive_root/evil\"
python3 - '${TEST_DIR}/small-traversal.tgz' <<'PY'
import io
import sys
import tarfile

data = b'unsafe\n'
info = tarfile.TarInfo('../evil')
info.size = len(data)
with tarfile.open(sys.argv[1], 'w:gz') as tar:
    tar.addfile(info, io.BytesIO(data))
PY
extraction_marker='${TEST_DIR}/small-extraction-called'

get_small_checksum() {
    return 1
}

wget() {
    case \"\$1\" in
        --help)
            return 0
            ;;
        -q)
            cp '${TEST_DIR}/small-traversal.tgz' \"\$3\"
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

tar() {
    case \"\$1\" in
        xzf)
            printf 'called\n' > \"\$extraction_marker\"
            return 1
            ;;
    esac
    command tar \"\$@\"
}

if download_tailscale_small '1.2.3' 'amd64' '${TEST_DIR}/target' 2>/dev/null; then
    echo 'small download accepted unsafe archive member'
    exit 1
fi

[ ! -f \"\$extraction_marker\" ] || { echo 'unsafe small archive reached extraction'; exit 1; }
"
    assert_success
}

@test "download_tailscale_official uses isolated temp paths for concurrent downloads" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
DOWNLOAD_BASE='https://example.test/stable'
TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD=1
export TAILSCALE_ALLOW_UNVERIFIED_DOWNLOAD

archive_root='${TEST_DIR}/archive-root'
mkdir -p \"\$archive_root/tailscale_1.2.3_amd64\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscale\"
printf '#!/bin/sh\n' > \"\$archive_root/tailscale_1.2.3_amd64/tailscaled\"
dest_log='${TEST_DIR}/download-dests.log'

wget() {
    case \"\$1\" in
        -qO-) return 1 ;;
        --help) return 0 ;;
        -q)
            printf '%s\n' \"\$3\" >> \"\$dest_log\"
            sleep 1
            tar czf \"\$3\" -C \"\$archive_root\" tailscale_1.2.3_amd64
            return 0
            ;;
    esac
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target-a' &
pid_a=\$!
download_tailscale_official '1.2.3' 'amd64' '${TEST_DIR}/target-b' &
pid_b=\$!
wait \"\$pid_a\"
wait \"\$pid_b\"

[ -f '${TEST_DIR}/target-a/tailscale' ] || { echo 'target-a missing'; exit 1; }
[ -f '${TEST_DIR}/target-b/tailscale' ] || { echo 'target-b missing'; exit 1; }

count=\$(sort -u \"\$dest_log\" | wc -l | tr -d ' ')
[ \"\$count\" = '2' ] || { echo 'download temp paths collided'; cat \"\$dest_log\"; exit 1; }
"
    assert_success
}
