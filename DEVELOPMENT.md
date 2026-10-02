# Development

## Supported environment

Use macOS 13 or later and Swift 5.9 or later (the package tools version is 5.9). CI runs on macOS 15 with Xcode 16.4 / Swift 6.1. The only runtime package dependency is exact-pinned TOMLKit 0.6.0, which vendors the MIT-licensed toml++ 3.4.0 parser and builds it as C++17. Swift's formatter is supplied by Xcode; CI does not install floating tools.

Check your environment:

```sh
swift --version
xcode-select -p
xcrun --find swift-format
```

If Swift or Xcode is missing, install the Xcode Command Line Tools with `xcode-select --install`, select a supported Xcode with `sudo xcode-select --switch <Xcode.app>/Contents/Developer`, then rerun these checks. Do not install unrelated tools as a workaround.

## Nix development shell and package

The flake supports `aarch64-darwin` and `x86_64-darwin`. The default development shell is unchanged: its explicit Nix packages are Git and GNU Make, while Swift and `swift-format` come from the selected Apple Xcode toolchain. Install Nix with flakes enabled and select Xcode before entering the shell. Nix does not install or select Xcode for you. The `nixpkgs-26.05-darwin` pin preserves Intel macOS support; verify that a replacement pin still supports `x86_64-darwin`.

```sh
nix flake show --all-systems
nix develop
make check
```

To run the project gate without opening an interactive shell, use `nix develop -c make check`. If the Xcode checks above fail, select or install Xcode before running the gate.

The flake also exposes `packages.<system>.default` and `packages.<system>.aerospace-gestures`. These build from this checkout with nixpkgs Swift/SwiftPM; they do not download release archives. `nix/workspace-state.json` and `nix/default.nix` pin TOMLKit to the exact `Package.resolved` revision and fixed-output hash so SwiftPM does not resolve the network during the sandboxed build. When `Package.resolved` changes, regenerate both files with the `swiftpm2nix` version from the locked nixpkgs input and review the resulting revision and hash together.

```sh
nix build .#
nix flake check
```

The Nix derivation cannot run Swift package tests because nixpkgs SwiftPM on Darwin lacks Apple's `xctest` runner. Run `make check` as the canonical test gate before accepting package changes; `nix flake check` verifies that the source package builds. Validate both architectures on native runners because Nix does not cross-build this macOS package.

## Find and claim work

1. Discover tasks in `plans/todo/`; check `depends_on` and the acceptance criteria.
2. Claim one task by moving its board status to `doing` before implementation. Do not start dependent tasks before their dependency is accepted.
3. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before changing module boundaries. Keep private APIs and effects out of the domain.

## Implement with feedback

- Write a failing focused test first when behavior can be tested deterministically; use injected adapters and temporary homes for effects.
- Run focused tests while iterating, for example `swift test --filter GestureCoreTests` or `swift test --filter GestureInfrastructureTests`.
- `make test` runs all deterministic tests. Tests must not access real trackpad hardware, show GUI prompts, mutate launchd, or install services.
- `make check` is the single normal gate for local work, hooks, and CI. Success writes exactly `true` to stdout. Failure writes `false` first, bounded diagnostics, a local full-log path, and returns nonzero. Logs live under ignored `.tmp/check/` (the gate retains only the latest ten); do not commit them. If it fails, inspect the reported log, fix the cause, then rerun `make check`.
- The gate builds with compiler warnings treated as errors, runs guardrail failure-path checks and all Swift tests. If Swift is missing, repair the Xcode/toolchain selection above; if a test or build fails, reproduce it with `make test` or `swift build -Xswiftc -warnings-as-errors` before changing code.

## Formatting and analysis

Formatting is explicit; checks never rewrite source:

```sh
make format       # intentional rewrite using Xcode's swift-format
make format-check # strict non-mutating check
make coverage     # all tests with Swift coverage instrumentation
```

After formatting, inspect the diff and rerun focused tests and `make check`. If formatting reports issues, use `make format` and review every changed file; do not disable the check by silently reformatting during commit. Coverage informs risk review; there is no arbitrary 100% threshold. Prioritize recognition/config rejection, command launch/busy/timeout/stop failures, and adapter ownership; private ABI and physical gestures remain manual because they cannot be made deterministic in unit tests. Architecture/security analysis and manual hardware testing are separate from the normal gate. If a dependency direction is violated (for example, Core imports an infrastructure module), move the effect behind the existing outer boundary and restore the SwiftPM dependency direction; do not add a source-regex architecture checker.

## Hooks

Hooks are versioned in `.githooks/` and call the same canonical gate as CI. Install only by explicit request:

```sh
make hooks-install
make hooks-check
```

Installation refuses to replace an effective (local or global) external `core.hooksPath` or bypass any executable non-sample hook in Git's default hooks directory, including symlinked hooks. Merge existing custom behavior manually into `.githooks/`, or retain your setup and run `make check` yourself. If hooks are not installed, `make hooks-check` explains how to install them. Commit messages use Conventional Commits (`feat(cli): ...`, `fix: ...`); board commits such as `plans(new): ...` are also accepted. Invalid subjects are rejected by `commit-msg`.

## Commit, land, and release verification

Before committing, review focused coverage and regression risk, run `make check`, run applicable manual checks, and confirm `git status` contains only intended files. Make a conventional commit that references the task ID. Update the task board only after acceptance evidence and the code commit; record outstanding manual checks honestly. Never auto-push, publish, or install a user service as part of setup.

Releases are tag-driven: pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`, which runs `make check`, builds arm64 and amd64 archives deterministically (USTAR, zeroed timestamps), verifies architecture and `--help`, attests provenance, and publishes a GitHub release with the archives and generated SHA256SUMS. The runtime binary version is the single constant `CLIVersion.current` in `Sources/GestureCLIPolicy/CLIVersion.swift`; when releasing, set it to the tag version (without the `v` prefix) and keep the package metadata version in `flake.nix` aligned. The release workflow gates the packaged binary's `--version` output against the actual `GITHUB_REF_NAME` tag after extraction and fails closed on runtime drift. SwiftPM dependencies are fetched from the exact revision pinned in `Package.resolved`; there is no runner cache, so builds stay reproducible per pin. Before tagging, run `make check` and validate a local archive (`swift build --configuration release --triple <native-triple>`, package per the workflow, then smoke-test the extracted binary); the binary payload is not byte-reproducible across clean builds, so the published SHA256SUMS are authoritative. Then exercise the documented listen/configuration smoke test on the supported hardware. Tagging and publishing remain explicit human actions; Homebrew tap and Nix updates are separate manual steps.

Any new dependency needs a pinned resolution and a relevant license/security review. SwiftPM has no built-in vulnerability-audit command; inspect its resolved graph and advisories with available tooling rather than adding a fake audit gate. For security-sensitive integrations, add a targeted audit when there is a concrete dependency to assess.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the target graph, effect boundaries, configuration schema, test strategy, and private API risks.
