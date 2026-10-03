<p align="center">
  <img src="docs/brand/logo.svg" alt="AeroSpace Gestures — Triple Swipe logo" width="112" height="112">
</p>

<h1 align="center">AeroSpace Gestures</h1>

<p align="center"><strong>Small gesture. Your command.</strong></p>

macOS trackpad gestures do not directly run your [AeroSpace WM](https://github.com/nikitabobko/AeroSpace) commands. AeroSpace Gestures maps three-to-five-finger swipes and opt-in two-to-five-finger pinch-in/spread-out gestures to commands. Native macOS gestures still run; pinch delivery on real hardware has not been verified.

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

**Version note:** The v0.3.0 release does not include pinch bindings; this checkout does. To try it without replacing an installed binary, use `swift run aerospace-gestures` from this checkout (see [Usage](docs/USAGE.md)). `make install` refuses to replace an existing binary. Use `type -a aerospace-gestures` to identify an installed command; `--version` alone cannot distinguish this checkout from v0.3.0.

## Try it

Requires macOS 13+, a multitouch trackpad, and Swift 5.9+.

```sh
aerospace-gestures init ./config.toml   # once; does not overwrite an existing config
aerospace-gestures check ./config.toml
aerospace-gestures run ./config.toml
# To observe gestures without running commands:
aerospace-gestures listen start
```

Swipe **three fingers down**. The generated config binds that swipe to an “It's hooked!” popup; it has no pinch binding. Lift all fingers before another gesture; press Ctrl-C to stop. Use `listen start` to observe without running commands. Pinch bindings do not suppress macOS pinch-to-zoom, so test on a trackpad before assigning important commands.

To bind a pinch, edit `config.toml`. Every binding uses `fingers` and `direction`: swipes use 3–5 with `left`/`right`/`up`/`down`; pinches use 2–5 with `in`/`out`. The counts may overlap. For example:

```toml
# Top-level, independent from the swipe threshold.
pinch_threshold = 0.2

[[bindings]]
fingers = 3
direction = "down"
command = ["/usr/bin/open", "-a", "Calculator"]

[[bindings]]
fingers = 3
direction = "in"
command = ["/usr/bin/open", "-a", "Calculator"]

[[bindings]]
fingers = 4
direction = "out"
command = ["/usr/bin/open", "-a", "Calendar"]
```

Run the CLI with that file:

```sh
aerospace-gestures check ./config.toml
aerospace-gestures run ./config.toml
```

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

- [Usage](docs/USAGE.md): configure commands, listen safely, pause/reload from the menu, install, run a service, and troubleshoot.
- [Development](DEVELOPMENT.md): build, test, and contribute.
- [Architecture](docs/ARCHITECTURE.md): design and known risks.
- [Brand assets](docs/brand/README.md): Triple Swipe logo and menu-bar treatment.
