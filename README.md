# aerospace-gestures

Gestures extension for [AeroSpace WM](https://github.com/nikitabobko/AeroSpace)

Map three-, four-, or five-finger macOS trackpad swipes to commands.

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
