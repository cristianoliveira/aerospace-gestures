# Usage guide

For installation, see [README](../README.md#install). For bindings and sensitivity, see [Configuration](CONFIGURATION.md).

The executable and CLI are named `cafune`. Commands below use an installed binary. From a checkout, use `swift run cafune` instead. Cafuné uses new configuration, preferences, service, and state identities; it does not migrate or remove the previous product's files.

## Run

Requires macOS 13+ and a multitouch trackpad.

```sh
cafune init ./config.toml # once; does not overwrite an existing file
cafune check ./config.toml
cafune run ./config.toml
```

Swipe **three fingers down** to show the default “It's hooked!” popup. Lift all fingers before another gesture. Press Ctrl-C to stop.

## Try safely

Observe gestures without running commands:

```sh
cafune listen start
```

To test your configuration's sensitivity without executing commands:

```sh
cafune run ./config.toml --dry-run
```

Press Ctrl-C before starting another listener. If no events appear, grant your terminal **System Settings → Privacy & Security → Input Monitoring** permission, then restart the listener. Do not use sudo.

The app cannot suppress macOS gestures. Disable conflicts under **Trackpad → More Gestures**; also check Accessibility's three-finger dragging setting. Test your own trackpad and settings for gesture conflicts.

## Menu controls

Normal `run` adds a menu-bar icon:

- **Disable actions** pauses new commands but keeps listening. A running command is not cancelled.
- **Enable actions** resumes commands after you lift all fingers. Pause state resets on restart.
- **Disable app-specific gestures / Enable app-specific gestures** affects only bindings with an `app` bundle ID; generic bindings remain active. This preference is remembered across restarts in the `com.cafune` per-user defaults suite. It is separate from pause.
- **App-specific bindings first / Global bindings first** (development source after v0.7.0-alpha.1) selects which matching binding wins when both exist for the same gesture and modifiers. App-specific-first is the default; global-first falls back to the app-specific binding when no generic binding exists. This runtime menu choice is persisted separately from the enable toggle and does not change TOML or Nix settings. The choices appear only when app-scoped bindings are configured. Both choices apply on the next contact sequence; lift all fingers after selecting.
- **Reload configuration** applies edits to the active file. If validation fails, the previous configuration stays active; check the menu for the result.
- **Quit Cafuné** stops input, terminates any active command, writes final diagnostics, and exits.

Listen and dry-run modes never execute commands and have no menu-bar status item. Quitting a listener started by the built-in LaunchAgent leaves it stopped for this login because the agent does not restart successful exits. An external service manager may restart it.

## Upgrading from aerospace-gestures

Cafuné is a clean break. It does not copy, rewrite, or delete the old configuration, LaunchAgent, preferences, or state. The old and new binaries use separate state paths. Stop the old listener before starting Cafuné.

For an old foreground listener, press Ctrl-C. If the previous per-user LaunchAgent is loaded, unload it explicitly:

```sh
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.aerospace-gestures.plist"
```

If the old plist exists, archive it after confirming the job is unloaded so it cannot relaunch. Keep it and the old data until you have verified the new service:

```sh
archive_dir="$HOME/Library/LaunchAgents/previous-aerospace-gestures"
archive_plist="$archive_dir/com.aerospace-gestures.plist"
mkdir -p "$archive_dir"
if [ -e "$archive_plist" ] || [ -L "$archive_plist" ]; then
  printf 'Refusing to overwrite existing archive: %s\n' "$archive_plist" >&2
  exit 1
fi
mv "$HOME/Library/LaunchAgents/com.aerospace-gestures.plist" "$archive_plist"
```

If you want to keep your old configuration, copy it to Cafuné's new default path and validate it before installing the service. For a custom config path or `XDG_CONFIG_HOME`, copy the file manually to the equivalent `cafune` path instead; Cafuné does not relocate it.

```sh
new_config="$HOME/.config/cafune/config.toml"
mkdir -p "$(dirname "$new_config")"
if [ -e "$new_config" ] || [ -L "$new_config" ]; then
  printf 'Refusing to overwrite existing config: %s\n' "$new_config" >&2
  exit 1
fi
cp "$HOME/.config/aerospace-gestures/config.toml" "$new_config"
cafune check "$new_config"
```

Then install the new binary and service. The installer refuses to modify the previous LaunchAgent; its bootout, archive, and data-copy steps are manual. Cafuné does not migrate menu preferences or logs. The old files remain available for your own cleanup after verification.

Nix-managed LaunchAgents are root-owned and separate from the built-in per-user service. Update the Nix declaration and deployment to use `com.cafune`, the `CAFUNE_NIX_MANAGED` marker, `/etc/cafune/config.toml`, and a trusted store target ending in `-cafune.toml`. Unload the previous Nix-managed job through your Nix deployment before starting the new one. Do not edit the root-owned plist or symlink by hand.

The repository URL and historical release records retain their original `aerospace-gestures` names; this does not affect the Cafuné executable or its local identities.

## Optional per-user service

The built-in service expects the binary at `~/.local/bin/cafune`. From a checkout, `make install` creates it and refuses to overwrite an existing installation.

```sh
BIN="$HOME/.local/bin/cafune"
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

The listener emits the aggregate input summary every 60 seconds to Unified Logging (`com.cafune`, category `input`). Set `CAFUNE_INPUT_DIAGNOSTICS=1` for an expanded, timestamped summary at startup, every 10 seconds, and at shutdown. It prints the exact persistent log path at startup and writes only diagnostic lines to `~/Library/Logs/cafune/input-diagnostics.log` (0600 permissions, bounded to 1 MiB; old contents are cleared when the limit is reached). Stdout diagnostics continue if the file is unavailable:

Stop any existing listener first, including the service if it is running; restart it after the foreground capture. `listen start` observes input without loading gesture commands or executing actions.

```sh
CAFUNE_INPUT_DIAGNOSTICS=1 .build/release/cafune listen start
```

After stopping with Ctrl-C, retrieve the persistent diagnostics without copying other process output:

```sh
tail -n 20 ~/Library/Logs/cafune/input-diagnostics.log
```

The persistent file contains only fixed aggregate diagnostic lines—not gesture output, configured commands, or configuration contents. The existing Unified Logging summary and the opt-in expansion contain only fixed aggregate fields; the expansion adds raw HID publish/termination counts, Touch Pad filter match/nonmatch/invalid counts, tracked Touch Pad terminations, snapshot successes/last device count, and rebind attempts by reason. `snapshot_last_count=0` means the last successful snapshot was empty; `none` means no snapshot succeeded yet. Counters are cumulative for the process. No device IDs, GUIDs, addresses, product names, contact data, configuration contents, or command data are emitted. LaunchAgent stdout/stderr remain discarded; use Unified Logging for the existing summary in service runs.

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
cafune --help
cafune help service
cafune --version
```
