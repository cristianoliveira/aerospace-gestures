<p align="center">
  <img src="docs/brand/logo.svg" alt="AeroSpace Gestures — Triple Swipe logo" width="112" height="112">
</p>

<h1 align="center">AeroSpace Gestures</h1>

<p align="center"><strong>Small gesture. Your command.</strong></p>

A gestures extension for [AeroSpace WM](https://github.com/nikitabobko/AeroSpace)

Map three-, four-, or five-finger macOS trackpad swipes and two-finger pinch-in/spread-out gestures to commands.

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

## Try it

Requires macOS 13+, a multitouch trackpad, and Swift 5.9+.

```sh
aerospace-gestures init ./config.toml   # once; does not overwrite an existing config
aerospace-gestures check ./config.toml
aerospace-gestures run ./config.toml
# To observe gestures without running commands:
aerospace-gestures listen start
```

Swipe **three fingers down**. The generated config shows an “It's hooked!” popup. Lift your fingers before trying again; press Ctrl-C to stop. Other swipes may be logged but have no default command. Pinch bindings are opt-in and do not suppress macOS pinch-to-zoom; private API delivery and interaction with native zoom require real-trackpad validation.

To use your own commands, edit `config.toml`. Swipe bindings keep the existing `fingers` and `direction` fields; pinch bindings use a distinct `gesture` field and an independent relative-separation threshold:

```toml
# Top-level, independent from the swipe `threshold`.
pinch_threshold = 0.2

[[bindings]]
fingers = 3
direction = "down"
command = ["/usr/bin/open", "-a", "Calculator"]

[[bindings]]
gesture = "pinch_in"
command = ["/usr/bin/open", "-a", "Calculator"]

[[bindings]]
gesture = "pinch_out"
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

If you're having trouble, try these:

- Make sure you're using a multitouch trackpad.

This uses Apple's private `MultitouchSupport` framework. It does not suppress system gestures, and macOS may require Input Monitoring permission for your terminal. Do not use sudo.

## Guides

- [Usage](docs/USAGE.md): configure commands, listen safely, pause/reload from the menu, install, run a service, and troubleshoot.
- [Development](DEVELOPMENT.md): build, test, and contribute.
- [Architecture](docs/ARCHITECTURE.md): design and known risks.
- [Brand assets](docs/brand/README.md): Triple Swipe logo and menu-bar treatment.
