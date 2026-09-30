.PHONY: check test install format format-check coverage hooks-install hooks-check

check:
	@./scripts/check.sh

test:
	swift test
	@./scripts/test-install.sh

# First install only; an existing binary is never replaced or restarted.
install:
	swift build -c release
	@./scripts/install-binary.sh .build/release/aerospace-gestures "$(HOME)/.local/bin"

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
