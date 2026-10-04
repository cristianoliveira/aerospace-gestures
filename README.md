<p align="center">
  <img src="docs/brand/logo.svg" alt="AeroSpace Gestures — Triple Swipe logo" width="112" height="112">
</p>

<h1 align="center">AeroSpace Gestures</h1>

<p align="center"><strong>Small gesture. Your command.</strong></p>

macOS trackpad gestures do not directly run your [AeroSpace WM](https://github.com/nikitabobko/AeroSpace) commands. AeroSpace Gestures maps three-to-five-finger swipes and opt-in two-to-five-finger pinch-in/spread-out gestures to commands.

The **Triple Swipe** menu-bar icon gives you access to pause/resume and configuration reload. A small pause badge means actions are paused; the listener remains active. The icon follows the macOS menu-bar appearance.

## Install

From a checkout with [Nix](https://nixos.org/) flakes enabled:

```sh
nix profile install .
```

This builds the pinned source and SwiftPM dependency, then adds `aerospace-gestures` to your Nix profile. It does not create a config, service, or permission grant. If `~/.local/bin/aerospace-gestures` is already installed, check `type -a aerospace-gestures`: that older binary may appear before the Nix profile on your `PATH`.

Or build with Swift 5.9+ and install to `~/.local/bin` (the script will not replace an existing binary):

```sh
make install
```

Add `~/.local/bin` to your `PATH` for this installation method.

Or from Homebrew:

```sh
brew install cristianoliveira/tap/aerospace-gestures
```

**Version note:** The v0.3.0 release does not include pinch bindings; the v0.4.0 source does. To try the current source without replacing an installed binary, use `swift run aerospace-gestures` from this checkout (see [Usage](docs/USAGE.md)). `make install` refuses to replace an existing binary. Check `aerospace-gestures --version` and `type -a aerospace-gestures` before using an installed command. Nix-managed installs must update the pinned package source and rebuild.

## Try it

Requires macOS 13+, a multitouch trackpad, and Swift 5.9+.

```sh
aerospace-gestures init ./config.toml   # once; does not overwrite an existing config
aerospace-gestures check ./config.toml
aerospace-gestures run ./config.toml
# To observe gestures without running commands:
aerospace-gestures listen start
```

Swipe **three fingers down**. The generated config binds that swipe to an “It's hooked!” popup; it has no pinch binding. Lift all fingers before another gesture; press Ctrl-C to stop. Use `listen start` to observe without running commands.

## Example config

Save this as `config.toml` to open Calculator with a three-finger left swipe:

```toml
[[bindings]]
fingers = 3
direction = "left"
command = ["/usr/bin/open", "-a", "Calculator"]
```

Run `aerospace-gestures check ./config.toml` before using it. For AeroSpace commands, pinch bindings, and sensitivity settings, see the [Configuration guide](docs/CONFIGURATION.md).

## Uninstall

Stop any managed service first (see [Usage](docs/USAGE.md)). Then remove the installation with its original package manager.

For Nix:

```sh
nix profile remove aerospace-gestures
```

For Homebrew:

```sh
brew uninstall aerospace-gestures
```

For a repo installation, delete `~/.local/bin/aerospace-gestures`.

## Troubleshooting

If no events appear in `listen start`, check that a multitouch trackpad is connected and that your terminal has **Input Monitoring** permission. Restart the listener after granting permission. The private `MultitouchSupport` API may change, and this app cannot suppress conflicting system gestures. Do not use sudo. See [Usage](docs/USAGE.md) for safe checks and limitations.

## Guides

- [Configuration](docs/CONFIGURATION.md): properties, examples, command recipes, sensitivity tuning, and debugging.
- [Usage](docs/USAGE.md): listen safely, use menu controls, install, run a service, and troubleshoot.
- [Development](docs/DEVELOPMENT.md): build, test, and contribute.
- [Architecture](docs/ARCHITECTURE.md): design and known risks.
- [Brand assets](docs/brand/README.md): Triple Swipe logo and menu-bar treatment.
