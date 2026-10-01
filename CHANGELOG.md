# Changelog

## v0.2.0

**Breaking: configuration is TOML-only.** JSON configuration files are rejected; there is no migration or automatic conversion. Re-create your config from `aerospace-gestures init` (TOML popup example) or convert it by hand — see [docs/USAGE.md](docs/USAGE.md) for the schema.

- TOML configuration with the same schema (`threshold`, `[[bindings]]`); parse errors report line/column; all prior validation rules retained.
- New pinned dependency: TOMLKit 0.6.0 (MIT), which vendors the MIT-licensed toml++ 3.4.0 parser; no runtime network access. See `Package.resolved`.
- Nix development shell (`flake.nix`); Triple Swipe logo and menu-bar icon.
- Homebrew installation documented; release archives ship with SHA-256 checksums and provenance attestations.
