# Changelog

## v0.2.1

- Redesigned CLI help with discoverable commands, focused examples and service actions (`aerospace-gestures help <command>` or `<command> -h` / `<command> --help`).
- Added `aerospace-gestures -v` / `--version` and `aerospace-gestures version`.
- Added source-built default Nix flake packages for Apple silicon and Intel macOS (`nix profile install .`).
- CLI syntax errors now print the relevant structured help on stderr and exit nonzero; option-like arguments are no longer mistaken for config paths.
- Configuration remains TOML-only; no config change is needed when upgrading from v0.2.0.

## v0.2.0

**Breaking: configuration is TOML-only.** JSON configuration files are rejected; there is no migration or automatic conversion. Re-create your config from `aerospace-gestures init` (TOML popup example) or convert it by hand — see the [v0.2.0 usage guide](https://github.com/cristianoliveira/aerospace-gestures/blob/v0.2.0/docs/USAGE.md) for the schema.

- TOML configuration with the same schema (`threshold`, `[[bindings]]`); parse errors report line/column; all prior validation rules retained.
- New pinned dependency: TOMLKit 0.6.0 (MIT), which vendors the MIT-licensed toml++ 3.4.0 parser; no runtime network access. See `Package.resolved`.
- Nix development shell (`flake.nix`); Triple Swipe logo and menu-bar icon.
- Homebrew installation documented; release archives ship with SHA-256 checksums and provenance attestations.
