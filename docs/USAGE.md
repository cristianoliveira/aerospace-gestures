# Usage guide

Start with the [quick start](../README.md). This guide covers configuration, permissions, menu controls, installation, services, troubleshooting, and limitations.

**Before you bind commands:** this uses the private `MultitouchSupport` framework, whose ABI can change. The app observes touches but cannot suppress system gestures. The generated config binds only a three-finger-down swipe; pinch bindings are opt-in. Two-to-five-finger pinches have synthetic-test coverage, not real-trackpad validation. The v0.3.0 release does not include pinch support; build the current checkout to try it.

## First experiment: three fingers down → popup

```sh
swift run aerospace-gestures init ./config.toml # first-time setup only; refuses an existing file
swift run aerospace-gestures check ./config.toml
swift run aerospace-gestures run ./config.toml
```

Move three fingers down the trackpad. A dialog should say **“It's hooked!”**, then close after three seconds (or click OK). Lift all fingers before trying again. Ctrl-C in the terminal stops the listener.

`-h` / `--help` and `help <command>` print per-command usage (try `help service` for the service actions); `-v` / `--version` or `version` prints the binary version. CLI syntax errors print the relevant structured help on stderr and exit nonzero; successful help and version output goes to stdout and exits 0. The version flags are root-only: `check -v`, for example, is invalid syntax and prints focused `check` help.

The default configuration binds only three-finger down; other detected gestures may appear in the terminal but do nothing. `init` creates the file only when absent and never overwrites an existing file or symlink. No AeroSpace setup is needed. The popup uses a dialog rather than a notification banner, so it does not depend on notification settings; it may take focus.

If macOS also opens App Exposé, disable its conflicting gesture in **System Settings → Trackpad → More Gestures**. If no popup appears, use the listen-only steps below to check whether touch events arrive.

## Try safely

Requires macOS 13+, a multitouch trackpad, and a Swift 5.9+ toolchain (Xcode Command Line Tools: `xcode-select --install`).

```sh
swift run aerospace-gestures listen start
```

Swipe with three or four fingers while another application is focused. You should see `Receiving trackpad frames`, followed by direction events. Direction describes physical finger motion, independent of Natural Scrolling. With a binary built from this checkout, also try a two-to-five-finger pinch. Whether those contacts arrive depends on your trackpad and macOS settings. Ctrl-C stops the process. Listen mode never runs commands; `aerospace-gestures listen --help` shows its usage without starting devices.

If no frames arrive, check **System Settings → Privacy & Security → Input Monitoring** for your terminal, then restart the process. Permission requirements can vary with macOS; this tool does not bypass them. Do not use sudo.

Disable conflicting actions in **System Settings → Trackpad → More Gestures**, including Spaces/Mission Control gestures. Also check Accessibility's three-finger dragging setting. The helper does not change your settings.

## Configure commands

Use the [Configuration guide](CONFIGURATION.md) for file locations, a complete example, the property reference, AeroSpace and script recipes, sensitivity tuning, reload steps, and command-output debugging.

```sh
swift run aerospace-gestures check ./config.toml
swift run aerospace-gestures run ./config.toml --dry-run
# Press Ctrl-C before starting normal run, which enables commands:
swift run aerospace-gestures run ./config.toml
```

`check` validates without starting input. Dry-run tests recognition without running commands. Normal run loads the file at startup; use **Reload configuration** in the menu after edits. Invalid replacements leave the previous configuration active. See [validate and apply changes](CONFIGURATION.md#validate-and-apply-changes) for a safe edit cycle.

## Pause command actions

A normal `run` starts enabled and adds a small accessory menu-bar control. Choose **Disable actions** to keep listening, recognizing, and logging gestures while suppressing new command launches; an already-running command is not cancelled. Gestures seen while paused and callbacks queued before a toggle are dropped. After enabling actions again, each trackpad must report all fingers lifted before a fresh gesture can launch a command. The setting is session-only and resets to enabled on restart. `listen` and `run --dry-run` never show an enabling control and can never launch configured commands.

The **Triple Swipe** menu-bar icon is the AeroSpace Gestures logo. When actions are paused, it adds a small two-bar pause badge without changing the menu-bar item width. It uses a monochrome template so macOS controls its appearance. The menu and accessibility label distinguish **Actions enabled** from **Actions paused — listener active**; the icon is not a hardware-health indicator. Reload shows visible loading, success, or error feedback in the menu because LaunchAgent output is discarded. The same process owns the status item in foreground and LaunchAgent modes—there is no second listener, IPC process, or Quit menu action. Normal run requests accessory activation (no Dock icon) without an app bundle.

Pinch detection does not suppress macOS pinch-to-zoom or otherwise intercept native gestures. Whether the private MultitouchSupport API delivers pinch motion consistently, or how it interacts with system zoom on a real trackpad, remains unverified; manually test before relying on pinch bindings. Menu-bar pause/resume acceptance was manually verified on macOS 26.7 arm64 using a test-owned popup configuration and per-user LaunchAgent; that test job was removed. A later Nix-managed binary replacement was also followed by user-confirmed menu controls and the original popup, without a TCC change. Changed-config hot reload, failure feedback, login/logout, crash recovery, long-term binary/TCC identity, reconnect, sleep/wake, and other OS/hardware combinations remain unverified. LaunchAgent stdout/stderr are discarded, so paused-state frame logging was not directly observed.

## Install the binary

```sh
make install
"$HOME/.local/bin/aerospace-gestures" --help
```

`make install` builds the release executable and installs it at `~/.local/bin/aerospace-gestures` only if absent. It refuses to replace an existing binary or symlink and does not start/restart a service. No login item or service is installed automatically. This repository does not publish a signed installer; use the update procedure below before replacing an existing binary. If you declare a Nix-managed LaunchAgent, install the binary before activating it and do not also run `service install` for the same job.

## Optional per-user service

Install the executable first; service commands never build or replace it. `make install` is for first install only. Initialize and validate the configuration before service installation:

```sh
make install
"$HOME/.local/bin/aerospace-gestures" init # only if your config is absent
# Use the full configuration path printed by init:
"$HOME/.local/bin/aerospace-gestures" check "/full/path/from/init"
"$HOME/.local/bin/aerospace-gestures" service install
"$HOME/.local/bin/aerospace-gestures" service status
```

The service is a per-user GUI LaunchAgent at `~/Library/LaunchAgents/com.aerospace-gestures.plist`. `install` captures the current default config path, starts the service now, and enables launch at GUI login; reinstall after changing `XDG_CONFIG_HOME`. `stop` unloads it for this login but retains the plist; `start` loads it again; `restart` validates the captured config before reloading; `uninstall` removes only the managed plist and preserves the executable/config. `service status` reports plist ownership, launchd state/PID/last exit status, config path, a sanitized startup-failure category when available, and that trackpad responsiveness is unverified. The service and foreground `run`/`listen` share a kernel lock to prevent duplicate listeners.

The LaunchAgent waits for the foreground listener to release the shared lock, so a startup race does not create a KeepAlive retry loop; foreground `run`/`listen` still fail immediately on contention. The service does not sign the binary or change Input Monitoring/TCC permissions. Command stdout/stderr are discarded to `/dev/null`; `~/Library/Application Support/aerospace-gestures/startup-diagnostic.log` retains at most one private (0600), 128-byte fixed failure stage/category. It is overwritten by a later startup failure and cleared after successful input initialization. It never records command arguments/output, configuration contents, or touch coordinates. `service status` shows the category and launchd's last exit code; detailed error text is not retained. Known private-framework, missing-symbol, and no-device failures have separate categories; the API does not provide a definitive TCC-denial reason. Recording is best-effort: an unsafe or missing support directory is reported as unavailable for an installed service, and no startup failure is reported if the file could not be written.

### Service troubleshooting and updates

1. Run `"$HOME/.local/bin/aerospace-gestures" service status`. `running` proves only that a process exists, not that the trackpad sends frames or a gesture works.
2. Use the exact configuration path shown by status: `"$HOME/.local/bin/aerospace-gestures" check "/path/from-status"`. After editing the captured file, run `"$HOME/.local/bin/aerospace-gestures" service restart`; invalid configuration is rejected before unload.
3. If status reports an input startup failure (for example, framework/symbols unavailable, no devices, or generic initialization failure), confirm a trackpad is connected and check **System Settings → Privacy & Security → Input Monitoring** for the executable identity. The private API may fail without a specific permission error. The program does not grant or reset permissions. A successful process status still does not prove gesture responsiveness.
4. If a job repeatedly exits, run `"$HOME/.local/bin/aerospace-gestures" service stop` to unload it, inspect the reported last exit/diagnostic, then validate and run `"$HOME/.local/bin/aerospace-gestures" service start` or `"$HOME/.local/bin/aerospace-gestures" service restart` when ready. The plist uses `KeepAlive` with a 30-second throttle; real crash recovery has not been verified.
5. For a binary update, note the captured config path from status and stop the service before replacing the executable. Keep a backup and use the same stable path:

   ```sh
   BIN="$HOME/.local/bin/aerospace-gestures"
   "$BIN" service stop
   cp "$BIN" "$BIN.backup"
   cp .build/release/aerospace-gestures "$BIN"
   "$BIN" check "/captured/config/path"
   "$BIN" service restart
   ```

   Stable Input Monitoring/TCC identity after binary replacement is unverified; do not assume a Terminal permission check proves the LaunchAgent identity is authorized. If the update fails, restore with `cp "$BIN.backup" "$BIN"`, then run `"$BIN" service start`.
6. Trackpads are enumerated at startup. After reconnecting one, or after sleep/wake if input stops, run `"$HOME/.local/bin/aerospace-gestures" service restart`. Automatic recovery is not implemented or verified.

### Manual reliability matrix

These scenarios are deliberately not claimed as tested. The bounded TASK-0003 lifecycle check on macOS 26.7 arm64 used an empty configuration and exercised install/stop/start/restart/uninstall only; it did not test login sessions, crashes, configuration changes, binary replacement, permissions, physical gestures, reconnect, or sleep/wake.

| Scenario | Evidence |
| --- | --- |
| GUI login/logout | Not tested. `RunAtLoad` is configured; no logout/login cycle was performed. |
| Crash recovery | Not tested on a live LaunchAgent. `KeepAlive` and the 30-second throttle are covered by plist assertions only. |
| Edited configuration then restart | Invalid-config refusal and rollback are covered by deterministic service tests; changed-config behavior was not manually exercised. |
| Binary replacement / Input Monitoring identity | A later Nix-managed binary replacement preserved a working popup without a TCC change; identity stability across other updates remains unverified. |
| Trackpad reconnect | Not tested. Current recovery is `service restart`. |
| Sleep/wake | Not tested. If input stops, current recovery is `service restart`. |

## Behavior and limits

- One action per contact sequence, rearmed after all fingers lift. Stable two-to-five-finger pinches require radial motion from every contact; translation, rotation at near-constant spread, subthreshold jitter, and a single moving/outlier contact do not trigger a pinch.
- Swipes require all fingers to move together; small movements and ambiguous diagonals are ignored.
- Changing finger identities/count resets the movement origin before recognition.
- Each device has independent recognition state. Devices are enumerated at startup; restart after reconnecting a trackpad.
- Only one child command runs at a time. Gestures while busy are dropped, not queued.
- Child commands receive a termination signal after five seconds, then SIGKILL one second later if still running. Ctrl-C stops input and applies the same bounded termination to an active child before the CLI exits. This bounds the direct child, not subprocess trees; commands must not daemonize.
- No taps, holds, gesture suppression, automatic startup by default, or App Store/sandbox support.
- Private device callbacks and physical recognition have no automated hardware coverage. A three-finger popup was manually confirmed on Intel and arm64 macOS 26; other OS versions and stable TCC identity across binary replacement remain unverified.

For development, see [DEVELOPMENT.md](../DEVELOPMENT.md) and [ARCHITECTURE.md](ARCHITECTURE.md). Manual acceptance covered the default three-finger-down popup only; test additional bound directions, two-to-five-finger pinch recognition/rejection, and conflicting system actions separately before enabling AeroSpace commands.
