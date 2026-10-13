# Changelog

## Unreleased

- Fixed modifier sampling reporting an unknown state when macOS includes left/right device modifier bits alongside the corresponding generic Command, Option, Control, or Shift flag. Orphan device bits and unsupported Fn remain fail-closed.

## v0.5.0

**Compatibility:** Existing valid configurations need no migration; missing or empty `modifiers` means no modifiers. Matching is exact, so holding a supported modifier does not trigger an unmodified binding. Unknown root and binding properties now fail validation instead of being ignored.

**Hardware note:** Modifier flags are sampled from the current login session without capturing keyboard events. Modifier behavior in the GUI LaunchAgent/private multitouch callback path still needs hardware validation. Fn remains unsupported and fails closed; Caps Lock is ignored. Pinch gestures do not suppress native macOS pinch-to-zoom.

- Added exact Command/Option/Control/Shift modifier matching for swipe and pinch bindings. Modifier sets are pinned per device contact sequence; changes cancel until full lift.
- Added privacy-safe, aggregate input diagnostics in Unified Logging every 60 seconds, including bridge callback/rejection counts, frame filtering and queue delivery, device lifecycle counts, and callback age. Idle input remains unclassified.

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
