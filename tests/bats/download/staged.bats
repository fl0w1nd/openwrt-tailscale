#!/usr/bin/env bats
# tests/bats/download/staged.bats
# Migrated from tests/download.sh: test_verify_staged_binary_*, test_install_staged_*

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "verify_staged_binary accepts valid tailscaled binary" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage_dir='${TEST_DIR}/stage'
mkdir -p \"\$stage_dir\"
printf '#!/bin/sh\necho \"tailscaled 1.78.0\"\n' > \"\$stage_dir/tailscaled\"
chmod +x \"\$stage_dir/tailscaled\"
verify_staged_binary \"\$stage_dir\"
"
    assert_success
}

@test "verify_staged_binary rejects broken binary" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage_dir='${TEST_DIR}/stage'
mkdir -p \"\$stage_dir\"
echo 'not a binary' > \"\$stage_dir/tailscaled\"
chmod +x \"\$stage_dir/tailscaled\"
if verify_staged_binary \"\$stage_dir\" 2>/dev/null; then
    echo 'should have rejected broken binary'
    exit 1
fi
"
    assert_success
}

@test "verify_staged_binary prefers combined binary when both exist" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage_dir='${TEST_DIR}/stage'
mkdir -p \"\$stage_dir\"
printf '#!/bin/sh\necho \"combined 1.78.0\"\n' > \"\$stage_dir/tailscale.combined\"
chmod +x \"\$stage_dir/tailscale.combined\"
echo 'bad' > \"\$stage_dir/tailscaled\"
chmod +x \"\$stage_dir/tailscaled\"
verify_staged_binary \"\$stage_dir\"
"
    assert_success
}

@test "verify_staged_binary fails on empty directory" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage_dir='${TEST_DIR}/stage'
mkdir -p \"\$stage_dir\"
if verify_staged_binary \"\$stage_dir\" 2>/dev/null; then
    echo 'should have failed on empty directory'
    exit 1
fi
"
    assert_success
}

@test "install_staged handles official layout (separate binaries)" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage='${TEST_DIR}/stage'
target='${TEST_DIR}/target'
mkdir -p \"\$stage\" \"\$target\"
echo 'tailscaled-bin' > \"\$stage/tailscaled\"
echo 'tailscale-bin' > \"\$stage/tailscale\"
echo '1.78.0' > \"\$stage/version\"
echo 'official' > \"\$stage/source\"

install_staged \"\$stage\" \"\$target\"

[ -f \"\$target/tailscaled\" ] || { echo 'tailscaled missing'; exit 1; }
[ -f \"\$target/tailscale\" ] || { echo 'tailscale missing'; exit 1; }
[ \"\$(cat \"\$target/version\")\" = '1.78.0' ] || { echo 'version mismatch'; exit 1; }
[ \"\$(cat \"\$target/source\")\" = 'official' ] || { echo 'source mismatch'; exit 1; }
[ ! -f \"\$stage/tailscaled\" ] || { echo 'staged tailscaled not cleaned'; exit 1; }
"
    assert_success
}

@test "install_staged handles small/combined layout (symlinks)" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage='${TEST_DIR}/stage'
target='${TEST_DIR}/target'
mkdir -p \"\$stage\" \"\$target\"
echo 'combined-bin' > \"\$stage/tailscale.combined\"
echo '1.78.0' > \"\$stage/version\"
echo 'small' > \"\$stage/source\"

install_staged \"\$stage\" \"\$target\"

[ -f \"\$target/tailscale.combined\" ] || { echo 'combined missing'; exit 1; }
[ -L \"\$target/tailscale\" ] || { echo 'tailscale symlink missing'; exit 1; }
[ -L \"\$target/tailscaled\" ] || { echo 'tailscaled symlink missing'; exit 1; }
[ \"\$(readlink \"\$target/tailscale\")\" = 'tailscale.combined' ] || { echo 'wrong symlink target'; exit 1; }
[ \"\$(cat \"\$target/version\")\" = '1.78.0' ] || { echo 'version mismatch'; exit 1; }
"
    assert_success
}

@test "install_staged cleans old layout files on switch from small to official" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage='${TEST_DIR}/stage'
target='${TEST_DIR}/target'
mkdir -p \"\$stage\" \"\$target\"
echo 'old-combined' > \"\$target/tailscale.combined\"
echo 'tailscaled-bin' > \"\$stage/tailscaled\"
echo 'tailscale-bin' > \"\$stage/tailscale\"

install_staged \"\$stage\" \"\$target\"

[ ! -f \"\$target/tailscale.combined\" ] || { echo 'old combined binary still present'; exit 1; }
"
    assert_success
}

@test "install_staged cleans old layout files on switch from official to small" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage='${TEST_DIR}/stage'
target='${TEST_DIR}/target'
mkdir -p \"\$stage\" \"\$target\"
echo 'old-tailscaled' > \"\$target/tailscaled\"
echo 'old-tailscale' > \"\$target/tailscale\"
echo 'combined-bin' > \"\$stage/tailscale.combined\"

install_staged \"\$stage\" \"\$target\"

[ -L \"\$target/tailscale\" ] || { echo 'tailscale should be symlink'; exit 1; }
[ -L \"\$target/tailscaled\" ] || { echo 'tailscaled should be symlink'; exit 1; }
"
    assert_success
}

@test "install_staged restores old official layout when deploy fails" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

stage='${TEST_DIR}/stage'
target='${TEST_DIR}/target'
mkdir -p \"\$stage\" \"\$target\"
echo 'new-tailscaled' > \"\$stage/tailscaled\"
echo 'new-tailscale' > \"\$stage/tailscale\"
echo '2.0.0' > \"\$stage/version\"
echo 'official' > \"\$stage/source\"
echo 'old-tailscaled' > \"\$target/tailscaled\"
echo 'old-tailscale' > \"\$target/tailscale\"
echo '1.0.0' > \"\$target/version\"
echo 'small' > \"\$target/source\"

mv() {
    case \"\$2\" in
        \"\$target/tailscale\") return 1 ;;
    esac
    command mv \"\$@\"
}

if install_staged \"\$stage\" \"\$target\" 2>/dev/null; then
    echo 'install_staged should have failed'
    exit 1
fi

[ \"\$(cat \"\$target/tailscaled\")\" = 'old-tailscaled' ] || { echo 'old tailscaled not restored'; exit 1; }
[ \"\$(cat \"\$target/tailscale\")\" = 'old-tailscale' ] || { echo 'old tailscale not restored'; exit 1; }
[ \"\$(cat \"\$target/version\")\" = '1.0.0' ] || { echo 'old version not restored'; exit 1; }
[ \"\$(cat \"\$target/source\")\" = 'small' ] || { echo 'old source not restored'; exit 1; }
"
    assert_success
}

@test "create_symlinks refuses to overwrite non-managed commands" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

USER_BIN_DIR='${TEST_DIR}/usr-bin'
bin_dir='${TEST_DIR}/managed-bin'
mkdir -p \"\$USER_BIN_DIR\" \"\$bin_dir\"
printf 'existing command\n' > \"\$USER_BIN_DIR/tailscale\"

if create_symlinks \"\$bin_dir\" 2>/dev/null; then
    echo 'create_symlinks should have refused existing command'
    exit 1
fi

[ -f \"\$USER_BIN_DIR/tailscale\" ] || { echo 'existing command removed'; exit 1; }
[ \"\$(cat \"\$USER_BIN_DIR/tailscale\")\" = 'existing command' ] || { echo 'existing command changed'; exit 1; }
[ ! -e \"\$USER_BIN_DIR/tailscaled\" ] || { echo 'tailscaled link created after failure'; exit 1; }
"
    assert_success
}

@test "remove_symlinks only removes links for managed bin directories" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

USER_BIN_DIR='${TEST_DIR}/usr-bin'
managed='${TEST_DIR}/managed-bin'
other='${TEST_DIR}/other-bin'
mkdir -p \"\$USER_BIN_DIR\" \"\$managed\" \"\$other\"
ln -s \"\$managed/tailscale\" \"\$USER_BIN_DIR/tailscale\"
ln -s \"\$other/tailscaled\" \"\$USER_BIN_DIR/tailscaled\"

remove_symlinks \"\$managed\"

[ ! -e \"\$USER_BIN_DIR/tailscale\" ] && [ ! -L \"\$USER_BIN_DIR/tailscale\" ] || { echo 'managed tailscale link remained'; exit 1; }
[ -L \"\$USER_BIN_DIR/tailscaled\" ] || { echo 'other tailscaled link removed'; exit 1; }
[ \"\$(readlink \"\$USER_BIN_DIR/tailscaled\")\" = \"\$other/tailscaled\" ] || { echo 'other link target changed'; exit 1; }
"
    assert_success
}
