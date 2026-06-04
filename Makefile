# ============================================================================
# openwrt-tailscale Makefile
# ============================================================================
# Run `make help` to see all targets.

SHELL := /bin/sh

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

TEST_SHELL  ?= sh
TEST_MODULE ?=
REQUIRE_SHELLCHECK ?= 0
REQUIRE_SHFMT      ?= 0
E2E_TEST_FILES := \
    tests/bats/common/init_extra_env.bats \
    tests/bats/selfupdate/bundle.bats

# ShellCheck options. Suppression rules and the default shell dialect live
# in .shellcheckrc so that the same configuration is picked up by IDE
# integrations and so that scripts can override the dialect locally with
# `# shellcheck shell=bash` (otherwise -s sh would force POSIX everywhere).
SHELLCHECK_FLAGS ?= -x

# shfmt options. Tabs are forbidden by .editorconfig; we use 4 spaces with
# `case` indentation, switch-case alignment, and binary-op-at-line-start.
SHFMT_FLAGS ?= -i 4 -ci -bn -kp

# Glob list for shell scripts that must lint cleanly. The wildcard
# expansion runs against the working tree, so adding a new module under
# usr/lib/tailscale/ or scripts/dev/ is automatically picked up.
SHELL_SCRIPT_GLOBS := \
    tailscale-manager.sh \
    etc/init.d/tailscale \
    usr/bin/tailscale-update \
    usr/lib/tailscale/*.sh \
    scripts/build-small.sh \
    scripts/dev/*.sh \
    tests/*.sh

SHELL_SCRIPTS := $(sort $(wildcard $(SHELL_SCRIPT_GLOBS)))

COVERAGE_DIR              ?= coverage
COVERAGE_INCLUDE_PATTERNS := tailscale-manager.sh,usr/lib/tailscale,etc/init.d,usr/bin
COVERAGE_EXCLUDE_PATTERNS := tests,docs,build,dist,scripts/build-small.sh

# ----------------------------------------------------------------------------
# Targets
# ----------------------------------------------------------------------------

.DEFAULT_GOAL := help
.PHONY: help ci lint syntax check-sync shellcheck check-static \
        format format-check test test-bats test-e2e coverage clean print-scripts

## help: Show this help message.
help:
	@awk 'BEGIN { FS = ": "; printf "Usage: make <target>\n\nTargets:\n" } \
	      /^## [a-zA-Z_-]+:/ { sub(/^## /, "", $$0); split($$0, a, ":"); \
	          desc = substr($$0, length(a[1]) + 3); \
	          printf "  \033[36m%-15s\033[0m %s\n", a[1], desc }' $(MAKEFILE_LIST)

## ci: Run everything CI runs (lint + test).
ci: lint test

## lint: Static analysis (syntax + sync + shellcheck + LuCI checks).
lint: syntax check-sync shellcheck check-static

## syntax: Verify every shell script parses under POSIX sh.
syntax:
	@set -e; \
	for file in $(SHELL_SCRIPTS); do \
		sh -n "$$file" || { printf 'SYNTAX ERROR: %s\n' "$$file" >&2; exit 1; }; \
	done
	@printf 'syntax: %d shell script(s) OK\n' $(words $(SHELL_SCRIPTS))

## check-sync: Verify the inline COMMON_LIB fallback matches common.sh.
check-sync:
	@sh scripts/dev/check-sync.sh

## shellcheck: Run shellcheck on every script in SHELL_SCRIPTS.
shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELLCHECK_FLAGS) $(SHELL_SCRIPTS); \
	elif [ "$(REQUIRE_SHELLCHECK)" = "1" ]; then \
		printf 'shellcheck: required but not installed.\n' >&2; \
		exit 1; \
	else \
		printf 'shellcheck: not installed; skipping.\n  Install with: brew install shellcheck (macOS) or apt-get install shellcheck (linux).\n'; \
	fi

## check-static: Validate LuCI app structure, JSON files and library refs.
check-static:
	@for f in luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/config.js \
	          luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/status.js \
	          luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/maintenance.js \
	          luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale; do \
		[ -f "$$f" ] || { printf 'MISSING: %s\n' "$$f"; exit 1; }; \
	done
	@if command -v python3 >/dev/null 2>&1; then \
		for f in luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json \
		         luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json; do \
			python3 -m json.tool "$$f" >/dev/null || { printf 'INVALID JSON: %s\n' "$$f"; exit 1; }; \
		done; \
	fi
	@for f in luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/*.js; do \
		if grep -Fq 'luci.tailscale' "$$f"; then \
			printf 'Legacy rpc object in %s\n' "$$f"; exit 1; \
		fi; \
	done
	@for lib in common.sh jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do \
		[ -f "usr/lib/tailscale/$$lib" ] || { printf 'MISSING: usr/lib/tailscale/%s\n' "$$lib"; exit 1; }; \
	done
	@TAILSCALE_MANAGER_SOURCE_ONLY=1 sh -c '. ./tailscale-manager.sh; \
		for f in "$$LUCI_RPC_URL" "$$LUCI_MENU_URL" "$$LUCI_ACL_URL"; do \
			rel=$${f#$$REPO_BASE_URL/}; \
			[ -f "$$rel" ] || { printf "URL mismatch: %%s\n" "$$rel"; exit 1; }; \
		done' 2>/dev/null

## format: Auto-format all shell scripts with shfmt (modifies files).
format:
	@if ! command -v shfmt >/dev/null 2>&1; then \
		printf 'shfmt: not installed.\n  Install with: brew install shfmt (macOS) or apt-get install shfmt (linux).\n' >&2; \
		exit 1; \
	fi
	@shfmt -w $(SHFMT_FLAGS) $(SHELL_SCRIPTS)

## format-check: Verify all shell scripts are shfmt-formatted.
format-check:
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -d $(SHFMT_FLAGS) $(SHELL_SCRIPTS); \
	elif [ "$(REQUIRE_SHFMT)" = "1" ]; then \
		printf 'shfmt: required but not installed.\n' >&2; \
		exit 1; \
	else \
		printf 'shfmt: not installed; skipping.\n  Install with: brew install shfmt (macOS) or apt-get install shfmt (linux).\n'; \
	fi

## test: Run the shell test suite (default sh, override with TEST_SHELL).
test:
	@TEST_SHELL="$(TEST_SHELL)" SHELL_UNDER_TEST="$${SHELL_UNDER_TEST:-$(TEST_SHELL)}" TEST_MODULE="$(TEST_MODULE)" sh tests/run.sh

## test-bats: Run only the bats-based tests.
test-bats:
	@SHELL_UNDER_TEST="$${SHELL_UNDER_TEST:-$(TEST_SHELL)}" sh tests/run-bats.sh

## test-e2e: Run tagged POSIX-shell e2e tests (override with TEST_SHELL).
test-e2e:
	@TEST_SHELL="$(TEST_SHELL)" SHELL_UNDER_TEST="$${SHELL_UNDER_TEST:-$(TEST_SHELL)}" sh tests/run-bats.sh --filter-tags e2e $(E2E_TEST_FILES)

## coverage: Generate kcov coverage report into $(COVERAGE_DIR)/.
coverage:
	@if ! command -v kcov >/dev/null 2>&1; then \
		printf 'kcov: not installed; skipping coverage.\n  Install with: brew install kcov (macOS) or apt-get install kcov (linux).\n'; \
		exit 0; \
	fi
	@rm -rf "$(COVERAGE_DIR)"
	@mkdir -p "$(COVERAGE_DIR)"
	@kcov \
		--include-pattern=$(COVERAGE_INCLUDE_PATTERNS) \
		--exclude-pattern=$(COVERAGE_EXCLUDE_PATTERNS) \
		"$(COVERAGE_DIR)" \
		sh tests/run-bats.sh
	@printf 'coverage: report at %s/index.html\n' "$(COVERAGE_DIR)"

## print-scripts: Debug helper — print the SHELL_SCRIPTS list.
print-scripts:
	@printf '%s\n' $(SHELL_SCRIPTS)

## clean: Remove generated coverage / test artifacts.
clean:
	@rm -rf "$(COVERAGE_DIR)"
