# Development

Run commands from the repository root. Development and tests must not change trackpad settings, install services, or show GUI prompts.

## Setup

Requires macOS 13+, Swift 5.9+, and an Apple toolchain with `swift-format`.

```sh
swift --version
xcode-select -p
xcrun --find swift-format
swift build
```

If the toolchain is missing, run `xcode-select --install` or select your Xcode installation.

## Build and test

```sh
swift build
swift test --filter GestureCoreTests # focused feedback while editing
make check                          # required gate: build, tests, guardrails
```

`make check` prints `true` on success. On failure, it prints diagnostics and the full log path under `.tmp/check/`.

Additional checks:

| Command | Purpose |
| --- | --- |
| `make test` | Run Swift tests and installer tests. |
| `make format` | Format Swift source in place; review the diff. |
| `make format-check` | Check formatting without changing files. |
| `make coverage` | Run Swift tests with coverage instrumentation. |

With Funzzy installed, `fzz` watches changes and runs the configured gate. Use `fzz control status` to inspect it instead of starting a duplicate run.

## Make a change

1. Read [Architecture](ARCHITECTURE.md) before changing module boundaries.
2. Write a failing focused test, then implement the change. Use injected dependencies and temporary files; do not access real devices or launchd in tests.
3. Test success and failure paths. Review coverage where behavior changed.
4. Update the relevant guide: [Usage](USAGE.md) for operating the app, [Configuration](CONFIGURATION.md) for settings. Keep instructions short; link instead of repeating details.
5. Run `make check`, inspect the diff, and commit with a Conventional Commit message such as `fix: reject invalid binding`.

Keep hardware checks separate from automated tests. Record what you actually tested; do not claim physical gesture support from synthetic tests alone. Do not commit `.tmp/` logs.

Optional Git hooks:

```sh
make hooks-install
make hooks-check
```

The installer refuses conflicting hooks. Keep your existing setup and run `make check` manually if needed.

## Nix

```sh
nix develop          # development shell; Swift still comes from Apple tooling
nix build .#         # build the package
nix flake check      # validate the package build
```

Supported systems: `aarch64-darwin` and `x86_64-darwin`. Nix package checks do not run Swift tests; use `make check` too. Test each architecture on a native runner.

When changing `Package.resolved`, regenerate `nix/default.nix` and `nix/workspace-state.json` with the locked `swiftpm2nix` version. Review dependency pins, hashes, and licenses together.

## Release

1. Set `CLIVersion.current` in `Sources/GestureCLIPolicy/CLIVersion.swift` and the version in `flake.nix` to the intended release version.
2. Run `make check`, build with `swift build -c release`, and verify the binary's `--version` and `--help`.
3. Perform the [usage smoke test](USAGE.md#run) on supported hardware.
4. After approval, push a matching `vX.Y.Z` tag. The [release workflow](../.github/workflows/release.yml) builds and publishes arm64 and amd64 archives.

Homebrew tap and Nix package updates are separate manual steps. Do not publish or change an installed service as part of ordinary development.
