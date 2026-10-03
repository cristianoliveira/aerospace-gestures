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

```sh
swift run aerospace-gestures init ./config.toml # first-time setup only
swift run aerospace-gestures check ./config.toml
swift run aerospace-gestures run ./config.toml --dry-run
swift run aerospace-gestures run ./config.toml
```

`init` accepts an optional path. Without one, its default is `$XDG_CONFIG_HOME/aerospace-gestures/config.toml` when `XDG_CONFIG_HOME` is an absolute nonempty path; otherwise it is `~/.config/aerospace-gestures/config.toml`. `check` and `run` require a configuration path so an omitted operand produces command usage instead of acting on an implicit file. Relative paths are resolved from the current working directory. `run` and `listen start` never create configuration implicitly. Use `check <path>` to validate a file without starting trackpad input.

The default init example runs `/usr/bin/osascript` to show the proven popup; child output is discarded by default; the same popup is tracked as [`config.probe.toml`](../config.probe.toml). For a harmless command-only sample, see [`config.example.toml`](../config.example.toml) (which uses `/bin/echo`). Successful execution appears as `Command exited with status 0`. AeroSpace's `exec-and-forget` is its own configuration directive, not an executable for this app.

For AeroSpace, find its absolute path:

```sh
command -v aerospace
```

Replace a binding with your path, for example:

```toml
[[bindings]]
fingers = 3
direction = "left"
command = ["/opt/homebrew/bin/aerospace", "focus", "left"]
```

To bind a pinch, put `pinch_threshold` before the binding tables (top-level). Use the same `fingers` and `direction` keys as a swipe. Here three-finger pinch and three-finger swipe can coexist; only the matching direction runs its command:

```toml
pinch_threshold = 0.2

[[bindings]]
fingers = 3
direction = "left"
command = ["/usr/bin/open", "-a", "Calculator"]

[[bindings]]
fingers = 3
direction = "in"
command = ["/usr/bin/open", "-a", "Calendar"]

[[bindings]]
fingers = 4
direction = "out"
command = ["/usr/bin/open", "-a", "Calendar"]
```

Configuration:

- Swipe bindings use `fingers` 3, 4, or 5 and `direction` `left`, `right`, `up`, or `down`.
- Pinch bindings use `fingers` 2, 3, 4, or 5 and `direction = "in"` (together) or `direction = "out"` (apart). Pinch and swipe may share a finger count. Two-finger swipes are not supported. The obsolete `gesture` field is rejected.
- `command`: executable's absolute path followed by separate arguments. No shell expansion, pipes, or redirection. For more complex actions, invoke your own executable script. The child always receives `/dev/null` as stdin; test commands with stdin closed and pass `--no-stdin` if the tool supports it. By default, stdout and stderr are discarded and only the exit status appears in gesture logs.
- `debug_command_output`: optional, defaults to `false`. Set `true` temporarily to inspect command stdout/stderr. Foreground `run` forwards them to the matching terminal streams. Managed LaunchAgents (including Nix-managed ones) append tagged output to `~/Library/Application Support/aerospace-gestures/command-output.log`; inspect it with `tail -f "$HOME/Library/Application Support/aerospace-gestures/command-output.log"`. The file is mode `0600` and capped at 1 MiB; raw output is capped at 64 KiB per command (plus small stream labels), after which output is drained and discarded to avoid blocking the command. Reloading configuration changes the setting for future commands. Disable it when finished; the log persists until you remove it with `rm "$HOME/Library/Application Support/aerospace-gestures/command-output.log"`. If the managed log path is unsafe or unavailable, capture is disabled and a warning goes to the macOS unified log; configured commands still run. Command output can contain credentials or other sensitive data; enabling this option deliberately exposes that output in your terminal or private log.
- `threshold`: optional swipe threshold, defaults to `0.15`, allowed range `0.02`–`0.8`. Measured as normalized trackpad displacement, not pixels. Lower values are more sensitive.
- `pinch_threshold`: optional, defaults to `0.2`, allowed range `0.05`–`0.5`. It measures relative change in the initial distance between two contacts, or in the centroid-relative RMS radius for three to five; it is independent of the swipe threshold. Both two-finger contacts must move in opposite radial directions; all three-to-five contacts must move radially with a consistent scale. Small/jittery or asymmetric pinches may not register. Baselines below `0.04` separation for two contacts or `0.02` RMS radius for three to five are ignored.

Put `debug_command_output = true` at the **top level**, before any `[[bindings]]` table; a value inside a binding does not enable capture. Remove it or set it to `false` when debugging is done.

Configuration is loaded at startup. In normal `run`, choose **Reload configuration** from the menu to read and validate the active file without restarting the input listener. A successful swap preserves pause state and running commands, discards queued old-config frames, and requires active fingers to lift before dispatch; a failure keeps the previous config and shows an error in the menu. The `debug_command_output` setting follows the active configuration and affects future command launches; a running command keeps its original output destination. For a Nix-managed LaunchAgent marked with `AEROSPACE_GESTURES_NIX_MANAGED=1`, reload rereads the trusted root-owned plist and stable `/etc/aerospace-gestures/config.toml` symlink on each request, so a rebuilt store config is picked up without changing plist argv. Foreground/manual runs keep their original config path. Listen and dry-run have no reload control. Duplicate bindings are rejected. Only use configuration/scripts you trust: commands run with your account's permissions.

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
