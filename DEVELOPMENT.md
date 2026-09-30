# Development

## Supported environment

Use macOS 13 or later and Swift 5.9 or later (the package tools version is 5.9). CI runs on macOS 15 with Xcode 16.4 / Swift 6.1. No third-party runtime or package dependencies are currently used. Swift's formatter is supplied by Xcode; CI does not install floating tools.

Check your environment:

```sh
swift --version
xcode-select -p
xcrun --find swift-format
```

If Swift or Xcode is missing, install the Xcode Command Line Tools with `xcode-select --install`, select a supported Xcode with `sudo xcode-select --switch <Xcode.app>/Contents/Developer`, then rerun these checks. Do not install unrelated tools as a workaround.

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

There is no release workflow yet. Before a future release, verify locally with `swift build -c release` and `swift test`, then exercise the documented listen/configuration smoke test on the supported hardware. Creating a release/publishing remains an explicit human action.

Any new dependency needs a pinned resolution and a relevant license/security review; do not add an audit command for an empty dependency graph. For security-sensitive integrations, add a targeted audit when there is a concrete dependency to assess.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the target graph, effect boundaries, configuration schema, test strategy, and private API risks.
