<p align="center">
  <img src="docs/brand/logo.svg" alt="Cafuné — Triple Swipe logo" width="112" height="112">
</p>

<h1 align="center">Cafuné</h1>

<p align="center"><strong>Small gesture. Your command.</strong></p>

Cafuné maps three-to-five-finger swipes and opt-in two-to-five-finger pinch-in/spread-out gestures to macOS commands. Use it with [AeroSpace WM](https://github.com/nikitabobko/AeroSpace) or run scripts, apps, and other tools.

`cafune` is the executable and canonical CLI. Cafuné uses new local configuration, preference, service, and state identities; upgrades from `aerospace-gestures` require a manual transition. See the [upgrade notes](docs/USAGE.md#upgrading-from-aerospace-gestures).

Use the menu-bar icon to pause commands or reload your configuration. The v0.7.0-alpha.1 pre-release also adds experimental app-scoped bindings and a separate persisted toggle.

## Install

Requires macOS 13+ and a multitouch trackpad. Choose one method:

- Homebrew: `brew install cristianoliveira/tap/aerospace-gestures` (the tap formula keeps its existing name and must be updated separately for Cafuné releases).
- Nix, from a checkout with flakes enabled: `nix profile install .`
- Build from a checkout with Swift 5.9+: `make install` (installs to `~/.local/bin`; add it to your `PATH`).

`make install` will not replace an existing binary; see the [update steps](docs/USAGE.md#service-troubleshooting-and-updates) if you use the built-in service. If several versions are installed, use `type -a cafune` to see which one runs.

## Try it

```sh
cafune init ./config.toml   # once; does not overwrite an existing config
cafune check ./config.toml
cafune run ./config.toml
```

Swipe **three fingers down** to show the example popup. Press Ctrl-C to stop. To observe gestures without running commands, use `cafune listen start`.

## Example config

Save this as `config.toml` to open Calculator with a three-finger left swipe:

```toml
[[bindings]]
fingers = 3
direction = "left"
command = ["/usr/bin/open", "-a", "Calculator"]
```

## Troubleshooting

If no gestures appear, grant your terminal **Input Monitoring** permission and restart the listener. See the [Usage guide](docs/USAGE.md) for service management and other checks.

## Guides

[Configuration](docs/CONFIGURATION.md) · [App integrations: Herdr and Brave](docs/INTEGRATIONS.md) · [Usage](docs/USAGE.md) · [Development](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md)
