SHELL_SCRIPTS := tailscale-manager.sh etc/init.d/tailscale usr/bin/tailscale-update usr/lib/tailscale/common.sh tests/run.sh scripts/build-pages.sh
SHELLCHECK_FLAGS := -s sh -e SC1091,SC3043
TEST_SHELL ?= sh

.PHONY: ci lint syntax check-sync shellcheck check-static test

ci: lint test

lint: syntax check-sync shellcheck check-static

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
	@for lib in common.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do \
		[ -f "usr/lib/tailscale/$$lib" ] || { printf 'MISSING: usr/lib/tailscale/%s\n' "$$lib"; exit 1; }; \
	done
	@TAILSCALE_MANAGER_SOURCE_ONLY=1 sh -c '. ./tailscale-manager.sh; \
		for f in "$$LUCI_RPC_URL" "$$LUCI_MENU_URL" "$$LUCI_ACL_URL"; do \
			rel=$${f#$$RAW_BASE_URL/}; \
			[ -f "$$rel" ] || { printf "URL mismatch: %%s\n" "$$rel"; exit 1; }; \
		done' 2>/dev/null

test:
	@TEST_SHELL="$(TEST_SHELL)" sh tests/run.sh
