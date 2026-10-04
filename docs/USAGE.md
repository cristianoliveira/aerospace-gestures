# Usage guide

For installation, see [README](../README.md#install). For bindings and sensitivity, see [Configuration](CONFIGURATION.md).

Commands below use an installed binary. From a checkout, use `swift run aerospace-gestures` instead.

## Run

Requires macOS 13+ and a multitouch trackpad.

```sh
aerospace-gestures init ./config.toml # once; does not overwrite an existing file
aerospace-gestures check ./config.toml
aerospace-gestures run ./config.toml
```

Swipe **three fingers down** to show the default “It's hooked!” popup. Lift all fingers before another gesture. Press Ctrl-C to stop.

## Try safely

Observe gestures without running commands:

```sh
aerospace-gestures listen start
```

To test your configuration's sensitivity without executing commands:

```sh
aerospace-gestures run ./config.toml --dry-run
```

Press Ctrl-C before starting another listener. If no events appear, grant your terminal **System Settings → Privacy & Security → Input Monitoring** permission, then restart the listener. Do not use sudo.

The app cannot suppress macOS gestures. Disable conflicts under **Trackpad → More Gestures**; also check Accessibility's three-finger dragging setting. Pinch delivery remains unverified on real hardware.

## Menu controls

Normal `run` adds a menu-bar icon:

- **Disable actions** pauses new commands but keeps listening. A running command is not cancelled.
- **Enable actions** resumes commands after you lift all fingers. Pause state resets on restart.
- **Reload configuration** applies edits to the active file. If validation fails, the previous configuration stays active; check the menu for the result.

Listen and dry-run modes never execute commands and have no enable or reload controls.

## Optional per-user service

The built-in service expects the binary at `~/.local/bin/aerospace-gestures`. From a checkout, `make install` creates it but refuses to overwrite an existing installation.

```sh
BIN="$HOME/.local/bin/aerospace-gestures"
"$BIN" init # skip if your default config already exists
# Use the full configuration path printed by init:
"$BIN" check "/full/path/from/init"
"$BIN" service install
"$BIN" service status
```

Installation starts the service and enables it at GUI login. It uses the [default config path](CONFIGURATION.md#create-or-locate-your-file), not necessarily `./config.toml`. Do not also install this service if Nix manages your LaunchAgent.

| Command | Action |
| --- | --- |
| `service status` | Show process state, config path, and available startup diagnostics. |
| `service stop` | Stop for this login; keep the service installed. |
| `service start` | Start a stopped service. |
| `service restart` | Validate the captured config, then restart. |
| `service uninstall` | Remove the service; keep the binary and config. |

Only one listener can run at a time. Stop the service before running a foreground listener. Service permissions may differ from your terminal's permissions.

### Service troubleshooting and updates

- **Running, but no gestures:** check Input Monitoring for the service executable. A running process does not prove input is working.
- **Wrong config:** use the path from `service status`. Reinstall the service if you change `XDG_CONFIG_HOME`.
- **Repeated exits:** stop the service, inspect `service status`, and validate its config before starting again.
- **Input stops after reconnect or sleep:** restart the service.
- **Updating the binary:** stop the service, back up the old binary, replace it at the same path, then validate the config and restart. If it fails, restore the backup. Permissions may need attention after replacement.

For configuration errors or missing command output, see [configuration troubleshooting](CONFIGURATION.md#troubleshooting). For private-API risks and test coverage, see [Architecture](ARCHITECTURE.md#manual-checks-and-risks).

## Command help

```sh
aerospace-gestures --help
aerospace-gestures help service
aerospace-gestures --version
```
