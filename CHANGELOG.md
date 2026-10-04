# Changelog

## Unreleased

## v0.4.0

**Upgrade note:** v0.3.0 rejects `direction = "in"` or `"out"` bindings. Upgrade the installed binary before adding pinch bindings; Nix-managed installs must update their pinned package source and rebuild.

- Added opt-in `debug_command_output = true` to show gesture-command stdout/stderr in foreground runs or a private, bounded log for managed services; output remains discarded by default.
- Added opt-in two-to-five-finger pinch-in and spread-out bindings using `fingers` with `direction = "in"` or `"out"`, plus an independent centroid-relative threshold; native macOS pinch-to-zoom is not suppressed.

## v0.3.0

**Breaking CLI invocation:** `check` and `run` now require an explicit `<config.toml>` path; use `listen start` instead of bare `listen`. Existing TOML config files need no migration; LaunchAgents installed by `aerospace-gestures service` already pass an explicit config path.

- Redesigned CLI help with discoverable commands, focused examples and service actions (`aerospace-gestures help <command>` or `<command> -h` / `<command> --help`).
- Added `aerospace-gestures -v` / `--version` and `aerospace-gestures version`.
- Added source-built default Nix flake packages for Apple silicon and Intel macOS (`nix profile install .`).
- CLI syntax errors now print the relevant structured help on stderr and exit nonzero; option-like arguments are no longer mistaken for config paths.
- Bare `check`, `run`, and `listen` now print focused command usage instead of implicitly using a default path or starting the listener.
- Configuration remains TOML-only; no config change is needed when upgrading from v0.2.0.

## v0.2.0

**Breaking: configuration is TOML-only.** JSON configuration files are rejected; there is no migration or automatic conversion. Re-create your config from `aerospace-gestures init` (TOML popup example) or convert it by hand — see the [v0.2.0 usage guide](https://github.com/cristianoliveira/aerospace-gestures/blob/v0.2.0/docs/USAGE.md) for the schema.

- TOML configuration with the same schema (`threshold`, `[[bindings]]`); parse errors report line/column; all prior validation rules retained.
- New pinned dependency: TOMLKit 0.6.0 (MIT), which vendors the MIT-licensed toml++ 3.4.0 parser; no runtime network access. See `Package.resolved`.
- Nix development shell (`flake.nix`); Triple Swipe logo and menu-bar icon.
- Homebrew installation documented; release archives ship with SHA-256 checksums and provenance attestations.
