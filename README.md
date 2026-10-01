<p align="center">
  <img src="docs/brand/logo.svg" alt="AeroSpace Gestures — Triple Swipe logo" width="112" height="112">
</p>

<h1 align="center">AeroSpace Gestures</h1>

<p align="center"><strong>Small gesture. Your command.</strong></p>

A gestures extension for [AeroSpace WM](https://github.com/nikitabobko/AeroSpace)

Map three-, four-, or five-finger macOS trackpad swipes to commands.

The **Triple Swipe** menu-bar icon gives you access to pause/resume and configuration reload. A small pause badge means actions are paused; the listener remains active. The icon follows the macOS menu-bar appearance.

## Install

From this repo (requires Swift 5.9+):

```sh
make install
```

This installs `~/.local/bin/aerospace-gestures`; add `~/.local/bin` to your `PATH`. It will not replace an existing binary.

Or from Homebrew:

```sh
brew install cristianoliveira/tap/aerospace-gestures
```

## Try it

Requires macOS 13+, a multitouch trackpad, and Swift 5.9+.

```sh
aerospace-gestures init   # once; does not overwrite an existing config
aerospace-gestures check
aerospace-gestures run
```

Swipe **three fingers down**. The default config shows an “It's hooked!” popup. Lift your fingers before trying again; press Ctrl-C to stop. Other swipes may be logged but have no default command.

To use your own config, save this as `config.toml`:

```toml
[[bindings]]
fingers = 3
direction = "down"
command = ["/usr/bin/open", "-a", "Calculator"]
```

Run the CLI with that file:

```sh
aerospace-gestures check ./config.toml
aerospace-gestures run ./config.toml
```

## Uninstall

For a Homebrew installation:

```sh
brew uninstall aerospace-gestures
```

For a repo installation, stop any managed service before deleting `~/.local/bin/aerospace-gestures` (see [Usage](docs/USAGE.md)).

## Troubleshooting

If you're having trouble, try these:

- Make sure you're using a multitouch trackpad.

This uses Apple's private `MultitouchSupport` framework. It does not suppress system gestures, and macOS may require Input Monitoring permission for your terminal. Do not use sudo.

## Guides

- [Usage](docs/USAGE.md): configure commands, listen safely, pause/reload from the menu, install, run a service, and troubleshoot.
- [Development](DEVELOPMENT.md): build, test, and contribute.
- [Architecture](docs/ARCHITECTURE.md): design and known risks.
- [Brand assets](docs/brand/README.md): Triple Swipe logo and menu-bar treatment.
