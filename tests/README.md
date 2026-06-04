# Test Suite

The test suite uses [bats-core](https://bats-core.readthedocs.io/) (Bash Automated Testing System).

## Prerequisites

Initialize the bats submodules (one-time setup):

```sh
git submodule update --init --recursive
```

Or if your system already has `bats` installed (`brew install bats-core` / `apt install bats`), the runner script will fall back to it automatically.

## Running Tests

```sh
# Run all tests
sh tests/run-bats.sh

# Run a specific module directory
sh tests/run-bats.sh tests/bats/json
sh tests/run-bats.sh tests/bats/firewall

# Run a single .bats file
sh tests/run-bats.sh tests/bats/version/parse.bats

# Run only e2e tests (requires dash/busybox)
sh tests/run-bats.sh --filter-tags e2e tests/bats/

# Run with TAP output
sh tests/run-bats.sh --formatter tap
```

The legacy entry `sh tests/run.sh` prints a deprecation notice and delegates to `run-bats.sh`.

## Directory Structure

```
tests/
├── run-bats.sh              # Main entry point
├── run.sh                   # Compatibility shim (deprecated)
└── bats/
    ├── _deps/               # git submodules (bats-core, bats-support, bats-assert, bats-file)
    ├── _fixtures/
    │   └── wget/            # HTTP response fixture files for wget stubs
    ├── _lib/
    │   ├── load.bash        # Unified helper loader (load ../_lib/load in .bats files)
    │   ├── setup.bash       # setup_test_env, teardown_test_env, source_lib, source_manager, bin_stub
    │   ├── mocks.bash       # Mock factories: mock_uci_*, mock_wget_scenario, mock_procd_recording, etc.
    │   └── run_in_sh.bash   # run_in_sh / run_sh for POSIX shell e2e tests
    ├── common/              # get_arch, migrate_config, get_effective_net_mode, init extra_env/args
    ├── version/             # validate_version_format, version_lt, API fetchers, list_*_versions
    ├── download/            # SHA256 checksum, staged binary, update/rollback flows, tailscale-update script
    ├── firewall/            # detect_firewall_backend, interface/zone/forwarding, remove_subnet_routing_config
    ├── json/                # json_escape, json_array_from_lines, cmd_json_status/install_info/peers
    ├── deploy/              # sync_managed_scripts, install flows, LuCI deploy/rollback, uninstall, uci config
    ├── selfupdate/          # check_script_update, do_self_update bundle, re-exec behaviour
    └── rpcd/                # rpcd exec bridge: list, dispatch, parameter validation
```

## Writing a New Test

Create a `.bats` file in the appropriate module directory:

```bash
#!/usr/bin/env bats
# tests/bats/version/my_new.bats

load ../_lib/load   # adjust depth: ../../_lib/load for nested dirs

setup() {
    setup_test_env
    source_lib version   # source usr/lib/tailscale/version.sh into current process
}

teardown() {
    teardown_test_env
}

@test "my function: describe what it should do" {
    result=$(my_function "input")
    assert_equal "expected" "${result}"
}

@test "my function: fails on bad input" {
    run my_function ""
    assert_failure
    assert_output --partial "error message"
}
```

Available assertions (from bats-assert):

| Assertion | Usage |
|-----------|-------|
| `assert_success` | `$status` is 0 |
| `assert_failure` | `$status` is non-zero |
| `assert_output "text"` | `$output` equals text |
| `assert_output --partial "text"` | `$output` contains text |
| `assert_equal "expected" "${actual}"` | values are equal |
| `assert_file_exists "/path"` | file exists |
| `assert_file_contains "/path" "text"` | file contains text |

## Mocking uci / wget / procd

### uci

```bash
setup() {
    setup_test_env
    # Mock with inline key=value pairs
    mock_uci_kv \
        "settings.net_mode=userspace" \
        "settings.bin_dir=/opt/tailscale"
    # All set/commit calls are logged to $UCI_CALLS_LOG
}

@test "something reads uci" {
    source_lib common
    run get_configured_net_mode
    assert_output "userspace"
    # Check a write happened
    run grep "set tailscale.settings" "${UCI_CALLS_LOG}"
    assert_success
}
```

Or write a custom stub with `bin_stub`:

```bash
bin_stub uci '#!/bin/sh
case "$*" in
    "-q get tailscale.settings.net_mode") echo "tun" ;;
    *) exit 1 ;;
esac'
```

### wget

Use a named fixture (place file at `tests/bats/_fixtures/wget/<name>.txt`):

```bash
mock_wget_scenario "official-valid"   # returns {"TarballsVersion":"1.76.1"}
```

Or write a custom stub:

```bash
bin_stub wget '#!/bin/sh
printf "%s" "{\"TarballsVersion\":\"1.82.0\"}"'
```

### procd

```bash
mock_procd_recording   # defines procd_open_instance, procd_set_param, etc.
# All calls written to $PROCD_CALLS

@test "start_service writes command" {
    start_service
    run grep "append command --tun" "${PROCD_CALLS}"
    assert_success
}
```

## e2e Tests

Tests that must run under `dash`/`busybox sh` are tagged with `e2e`:

```bash
# bats test_tags=e2e
@test "init extra_env overrides detected firewall mode" {
    run_in_sh dash "
. /path/to/script.sh
start_service
grep -Fq 'expected' /tmp/calls.log
"
    assert_success
}
```

Run only e2e tests: `sh tests/run-bats.sh --filter-tags e2e`

Set the shell via env: `SHELL_UNDER_TEST=dash sh tests/run-bats.sh`
