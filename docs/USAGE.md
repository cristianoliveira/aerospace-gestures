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

The app cannot suppress macOS gestures. Disable conflicts under **Trackpad → More Gestures**; also check Accessibility's three-finger dragging setting. Test your own trackpad and settings for gesture conflicts.

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

### Input diagnostics

The listener emits the existing aggregate input summary every 60 seconds to Unified Logging (`com.aerospace-gestures`, category `input`). Set `AEROSPACE_INPUT_DIAGNOSTICS=1` for an expanded, timestamped stdout summary every 10 seconds and at shutdown, suitable for a foreground repro log:

```sh
AEROSPACE_INPUT_DIAGNOSTICS=1 aerospace-gestures run 2>&1 | tee .tmp/validation/input-diagnostics.log
```

The existing summary and the opt-in expansion contain only fixed aggregate fields; the expansion adds raw HID publish/termination counts, Touch Pad filter match/nonmatch/invalid counts, tracked Touch Pad terminations, snapshot successes/last device count, and rebind attempts by reason. `snapshot_last_count=0` means the last successful snapshot was empty; `none` means no snapshot succeeded yet. Counters are cumulative for the process. No device IDs, GUIDs, addresses, product names, contact data, configuration contents, or command data are emitted. LaunchAgent stdout/stderr remain discarded; use Unified Logging for the existing summary in service runs.

`input_state=unclassified` is intentional: no callbacks can mean either an idle trackpad or a lost input stream. Compare callback, rejection, stale-drop, and main-queue counts; do not treat callback age alone as a failure signal.

### Service troubleshooting and updates

- **Running, but no gestures:** check Input Monitoring for the service executable. A running process does not prove input is working.
- **Wrong config:** use the path from `service status`. Reinstall the service if you change `XDG_CONFIG_HOME`.
- **Repeated exits:** stop the service, inspect `service status`, and validate its config before starting again.
- **Input stops after reconnect or sleep:** a public IORegistry observer watches HID Digitizer/Touch Pad topology events and coalesces them before rebinding all active Multitouch registrations. The listener process stays running, but unaffected trackpads may pause briefly during the rebind. Routine 5-second ticks retry failed registrations using retained handles; they do not enumerate or rebind active devices. If the observer is unavailable, a 60-second count-only watchdog globally rebinds only when the device count changes; a same-count swap can be missed. For a foreground repro, use the opt-in diagnostics command above and compare counters before/after one reconnect: raw HID service counts → Touch Pad filter counts → topology notifications/deliveries → snapshot success/count → rebind reason/registration counts → accepted frames. `topology_observer_armed=1` confirms setup only, not that a particular transport change was observed. Failed registrations retry up to three times; a later topology event starts a fresh retry budget. Observer failures include unreadable/missing usage properties or capacity exhaustion. The observer/filter and private Multitouch callback ABI are not verified across trackpad models or macOS versions.
- **Updating the binary:** stop the service, back up the old binary, replace it at the same path, then validate the config and restart. If it fails, restore the backup. Permissions may need attention after replacement.

For configuration errors or missing command output, see [configuration troubleshooting](CONFIGURATION.md#troubleshooting). For private-API risks and test coverage, see [Architecture](ARCHITECTURE.md#manual-checks-and-risks).

## Command help

```sh
aerospace-gestures --help
aerospace-gestures help service
aerospace-gestures --version
```
