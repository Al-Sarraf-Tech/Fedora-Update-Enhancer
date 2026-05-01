.PHONY: help test test-unit test-integration lint shellcheck shfmt audit install uninstall dry-run clean

PREFIX ?= /usr/local

help:
	@echo "Targets:"
	@echo "  make test            - run all bats tests"
	@echo "  make test-unit       - unit tests only"
	@echo "  make test-integration- integration tests only"
	@echo "  make lint            - shellcheck on all sources"
	@echo "  make shfmt           - format-check (advisory)"
	@echo "  make audit           - run S+ tier audit"
	@echo "  make install         - install to \$$PREFIX (default /usr/local) [requires sudo]"
	@echo "  make uninstall       - remove installation [requires sudo]"
	@echo "  make dry-run         - run elegant-updater --dry-run [requires sudo]"
	@echo "  make clean           - remove transient artifacts"

test: test-unit test-integration

test-unit:
	bats tests/unit/

test-integration:
	bats tests/integration/

lint:
	@find bin lib scripts -type f -name "*.sh" -print0 | xargs -0 shellcheck --severity=warning

shfmt:
	@find bin lib scripts -type f -name "*.sh" -print0 | xargs -0 shfmt -d

audit:
	@scripts/s-tier-audit.sh

install:
	sudo PREFIX=$(PREFIX) scripts/install.sh

uninstall:
	sudo PREFIX=$(PREFIX) scripts/uninstall.sh

dry-run:
	sudo bin/elegant-updater.sh --dry-run

clean:
	@rm -rf /tmp/fue-test.* /tmp/elegant-updater-repo-backup.* 2>/dev/null || true
