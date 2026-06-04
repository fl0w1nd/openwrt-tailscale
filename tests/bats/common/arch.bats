#!/usr/bin/env bats
# tests/bats/common/arch.bats
# Migrated from tests/common.sh: test_get_arch_mips_endianness, test_get_openwrt_arch_sources

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "get_arch: DISTRIB_ARCH mips_24kc returns mips (BE)" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo mips_24kc; }
uname() { echo mips; }
result=\$(get_arch)
[ \"\$result\" = 'mips' ] || { echo \"expected mips, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: DISTRIB_ARCH mipsel_24kc returns mipsle (LE)" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo mipsel_24kc; }
uname() { echo mips; }
result=\$(get_arch)
[ \"\$result\" = 'mipsle' ] || { echo \"expected mipsle, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: cpuinfo big endian returns mips" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo ''; }
uname() { echo mips; }
_real_grep=\$(command -v grep)
grep() {
    case \"\$*\" in
        *'little endian'*'/proc/cpuinfo'*) return 1 ;;
        *'big endian'*'/proc/cpuinfo'*)    return 0 ;;
        *) \"\$_real_grep\" \"\$@\" ;;
    esac
}
result=\$(get_arch)
[ \"\$result\" = 'mips' ] || { echo \"expected mips, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: cpuinfo little endian returns mipsle" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo ''; }
uname() { echo mips; }
_real_grep=\$(command -v grep)
grep() {
    case \"\$*\" in
        *'little endian'*'/proc/cpuinfo'*) return 0 ;;
        *'big endian'*'/proc/cpuinfo'*)    return 1 ;;
        *) \"\$_real_grep\" \"\$@\" ;;
    esac
}
result=\$(get_arch)
[ \"\$result\" = 'mipsle' ] || { echo \"expected mipsle, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: all mips sources fail defaults to mips (BE)" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo ''; }
uname() { echo mips; }
_real_grep=\$(command -v grep)
grep() {
    case \"\$*\" in
        *'little endian'*'/proc/cpuinfo'*) return 1 ;;
        *'big endian'*'/proc/cpuinfo'*)    return 1 ;;
        *) \"\$_real_grep\" \"\$@\" ;;
    esac
}
result=\$(get_arch)
[ \"\$result\" = 'mips' ] || { echo \"expected mips, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: uname mipsel always returns mipsle" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo ''; }
uname() { echo mipsel; }
result=\$(get_arch)
[ \"\$result\" = 'mipsle' ] || { echo \"expected mipsle, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: mips64 BE via DISTRIB_ARCH" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo mips64_octeonplus; }
uname() { echo mips64; }
result=\$(get_arch)
[ \"\$result\" = 'mips64' ] || { echo \"expected mips64, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_arch: mips64 LE via DISTRIB_ARCH" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
get_openwrt_arch() { echo mips64el_octeonplus; }
uname() { echo mips64; }
result=\$(get_arch)
[ \"\$result\" = 'mips64le' ] || { echo \"expected mips64le, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_openwrt_arch: DISTRIB_ARCH wins over apk and opkg" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
ROOT='${TEST_DIR}/root'
mkdir -p \"\$ROOT/etc/apk\" \"\$ROOT/etc/opkg\"
printf \"DISTRIB_ARCH='mips_24kc'\n\" > \"\$ROOT/etc/openwrt_release\"
echo 'x86_64' > \"\$ROOT/etc/apk/arch\"
result=\$(get_openwrt_arch \"\$ROOT\")
[ \"\$result\" = 'mips_24kc' ] || { echo \"expected mips_24kc, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_openwrt_arch: falls back to /etc/apk/arch when openwrt_release missing" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
ROOT='${TEST_DIR}/root'
mkdir -p \"\$ROOT/etc/apk\"
rm -f \"\$ROOT/etc/openwrt_release\"
echo 'mipsel_24kc' > \"\$ROOT/etc/apk/arch\"
result=\$(get_openwrt_arch \"\$ROOT\")
[ \"\$result\" = 'mipsel_24kc' ] || { echo \"expected mipsel_24kc, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_openwrt_arch: falls back to /etc/opkg.conf (skips all/noarch)" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
ROOT='${TEST_DIR}/root'
mkdir -p \"\$ROOT/etc\"
rm -f \"\$ROOT/etc/openwrt_release\" \"\$ROOT/etc/apk/arch\"
cat > \"\$ROOT/etc/opkg.conf\" <<'CONF'
dest root /
arch all 100
arch noarch 100
arch mips_24kc 10
CONF
result=\$(get_openwrt_arch \"\$ROOT\")
[ \"\$result\" = 'mips_24kc' ] || { echo \"expected mips_24kc, got \$result\"; exit 1; }
"
    assert_success
}

@test "get_openwrt_arch: returns empty string when no sources exist" {
    run_in_sh auto "
set -eu
. '${REPO_ROOT}/usr/lib/tailscale/common.sh'
ROOT='${TEST_DIR}/root-empty'
mkdir -p \"\$ROOT\"
result=\$(get_openwrt_arch \"\$ROOT\")
[ -z \"\$result\" ] || { echo \"expected empty, got \$result\"; exit 1; }
"
    assert_success
}
