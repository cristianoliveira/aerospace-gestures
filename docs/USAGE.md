# Usage guide

For installation, see [README](../README.md#install). For bindings and sensitivity, see [Configuration](CONFIGURATION.md).

The executable and CLI are named `cafune`. Commands below use an installed binary. From a checkout, use `swift run cafune` instead. Configuration, preferences, service labels, and state paths intentionally retain legacy `aerospace-gestures` identifiers.

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
- **Disable app-specific gestures / Enable app-specific gestures** affects only bindings with an `app` bundle ID; generic bindings remain active. This preference is remembered across restarts in the `com.aerospace-gestures` per-user defaults suite. It is separate from pause.
- **App-specific bindings first / Global bindings first** (development source after v0.7.0-alpha.1) selects which matching binding wins when both exist for the same gesture and modifiers. App-specific-first is the default; global-first falls back to the app-specific binding when no generic binding exists. This runtime menu choice is persisted separately from the enable toggle and does not change TOML or Nix settings. The choices appear only when app-scoped bindings are configured. Both choices apply on the next contact sequence; lift all fingers after selecting.
- **Reload configuration** applies edits to the active file. If validation fails, the previous configuration stays active; check the menu for the result.
- **Quit Cafuné** stops input, terminates any active command, writes final diagnostics, and exits.

Listen and dry-run modes never execute commands and have no menu-bar status item. Quitting a listener started by the built-in LaunchAgent leaves it stopped for this login because the agent does not restart successful exits. An external service manager may restart it.

## Upgrading from aerospace-gestures

Install the new `cafune` binary first. `make install` writes `~/.local/bin/cafune` and leaves the old executable untouched. Do not remove the old binary until the service migration is complete.

For an existing built-in per-user service, run `cafune service install`. It recognizes the exact owned legacy plist, unloads the old listener, updates the same plist to launch `cafune`, then checks the shared legacy instance lock before bootstrapping. If migration fails, it restores the prior plist. The LaunchAgent label and configuration path stay unchanged. `cafune service status` reports when migration is required; `start` and `restart` refuse to relaunch the old executable until you run `cafune service install`. `stop` and `uninstall` can still manage the recognized legacy plist.

For a foreground listener, stop the old process with Ctrl-C before starting `cafune`. Both versions use the same legacy instance lock, so a second listener cannot take over while the old one is active.

Nix-managed LaunchAgents are root-owned and separate from the built-in per-user service. Rebuild and deploy the managed plist so `ProgramArguments[0]` points to the new Nix-store `cafune` executable, then reload it through your Nix deployment. Keep the existing label, managed marker, `/etc/aerospace-gestures/config.toml` symlink, and trusted `*-aerospace-gestures.toml` target naming. Do not edit the root-owned plist or symlink by hand.

### Legacy identifiers retained for compatibility

These names are intentional data and service contracts, not the executable name. Keep them when upgrading:

| Purpose | Retained identity |
| --- | --- |
| Default config | `~/.config/aerospace-gestures/config.toml` or `$XDG_CONFIG_HOME/aerospace-gestures/config.toml` |
| User LaunchAgent | `com.aerospace-gestures` label and `~/Library/LaunchAgents/com.aerospace-gestures.plist` |
| User state and logs | `~/Library/Application Support/aerospace-gestures/` and `~/Library/Logs/aerospace-gestures/` |
| Persisted menu preferences | `com.aerospace-gestures` defaults suite |
| Nix-managed service | `/Library/LaunchAgents/com.aerospace-gestures.plist`, `/etc/aerospace-gestures/config.toml`, and the existing managed marker/trusted-store checks |

The executable and command are `cafune`; do not rename or delete these existing user data locations during the binary migration.

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

The listener emits the existing aggregate input summary every 60 seconds to Unified Logging (`com.aerospace-gestures`, category `input`). Set `AEROSPACE_INPUT_DIAGNOSTICS=1` for an expanded, timestamped summary at startup, every 10 seconds, and at shutdown. It prints the exact persistent log path at startup and writes only diagnostic lines to `~/Library/Logs/aerospace-gestures/input-diagnostics.log` (0600 permissions, bounded to 1 MiB; old contents are cleared when the limit is reached). Stdout diagnostics continue if the file is unavailable:

Stop any existing listener first, including the service if it is running; restart it after the foreground capture. `listen start` observes input without loading gesture commands or executing actions.

```sh
AEROSPACE_INPUT_DIAGNOSTICS=1 .build/release/cafune listen start
```

After stopping with Ctrl-C, retrieve the persistent diagnostics without copying other process output:

```sh
tail -n 20 ~/Library/Logs/aerospace-gestures/input-diagnostics.log
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
