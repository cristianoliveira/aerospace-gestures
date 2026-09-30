.PHONY: check test format format-check coverage hooks-install hooks-check

check:
	@./scripts/check.sh

test:
	swift test

format:
	xcrun swift-format format --in-place --recursive Sources Tests

format-check:
	xcrun swift-format lint --strict --recursive Sources Tests

coverage:
	swift test --enable-code-coverage

hooks-install:
	@./scripts/hooks-install.sh

hooks-check:
	@./scripts/hooks-check.sh
