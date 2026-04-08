SHELL_SCRIPTS := tailscale-manager.sh etc/init.d/tailscale usr/bin/tailscale-update usr/lib/tailscale/common.sh tests/run.sh
SHELLCHECK_FLAGS := -s sh -e SC1091,SC3043
TEST_SHELL ?= sh

.PHONY: ci lint syntax check-sync shellcheck test

ci: lint test

lint: syntax check-sync shellcheck

syntax:
	@set -e; \
	for file in $(SHELL_SCRIPTS); do \
		sh -n "$$file"; \
	done

check-sync:
	@set -e; \
	manager_tmp=$$(mktemp); \
	common_tmp=$$(mktemp); \
	awk 'BEGIN { in_block = 0; capture = 0 } $$0 == "if [ -f \"$$COMMON_LIB_PATH\" ]; then" { in_block = 1; next } in_block && $$0 == "else" { capture = 1; next } capture && $$0 == "fi" { exit } capture { print }' tailscale-manager.sh | sed 's/^    //' | grep -v '^[[:space:]]*#' | sed '/^[[:space:]]*$$/d' > "$$manager_tmp"; \
	grep -v '^[[:space:]]*#' usr/lib/tailscale/common.sh | sed '/^[[:space:]]*$$/d' > "$$common_tmp"; \
	if ! diff -u "$$common_tmp" "$$manager_tmp"; then \
		printf '%s\n' 'inline fallback in tailscale-manager.sh is out of sync with usr/lib/tailscale/common.sh'; \
		rm -f "$$manager_tmp" "$$common_tmp"; \
		exit 1; \
	fi; \
	rm -f "$$manager_tmp" "$$common_tmp"

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SHELLCHECK_FLAGS) $(SHELL_SCRIPTS); \
	elif [ "$(REQUIRE_SHELLCHECK)" = "1" ]; then \
		printf '%s\n' 'shellcheck is required but not installed.'; \
		exit 1; \
	else \
		printf '%s\n' 'shellcheck not found, skipping. Install with: brew install shellcheck'; \
	fi

test:
	@TEST_SHELL="$(TEST_SHELL)" sh tests/run.sh
