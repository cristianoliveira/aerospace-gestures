# aerospace-gestures

Small experimental macOS CLI: map three-, four-, or five-finger trackpad swipes to commands. Swift, a small C bridge, no third-party packages, no GUI or network access.

**Not a supported macOS gesture API.** This uses the private `MultitouchSupport` framework. Its ABI may change or crash on future macOS releases. It observes touches; it does **not** suppress system gestures. Real swipe behavior must be verified on your trackpad.

## First experiment: three fingers down → popup

```sh
swift run aerospace-gestures init # first-time setup only; refuses an existing file
swift run aerospace-gestures check
swift run aerospace-gestures run
```

Move three fingers down the trackpad. A dialog should say **“It's hooked!”**, then close after three seconds (or click OK). Lift all fingers before trying again. Ctrl-C in the terminal stops the listener.

The default configuration binds only three-finger down; other detected gestures may appear in the terminal but do nothing. `init` creates the file only when absent and never overwrites an existing file or symlink. No AeroSpace setup is needed. The popup uses a dialog rather than a notification banner, so it does not depend on notification settings; it may take focus.

If macOS also opens App Exposé, disable its conflicting gesture in **System Settings → Trackpad → More Gestures**. If no popup appears, use the listen-only steps below to check whether touch events arrive.

## Try safely

Requires macOS 13+, a multitouch trackpad, and a Swift 5.9+ toolchain (Xcode Command Line Tools: `xcode-select --install`).

```sh
swift run aerospace-gestures listen
```

Swipe with three or four fingers while another application is focused. You should see `Receiving trackpad frames`, followed by direction events. Direction describes physical finger motion, independent of Natural Scrolling. Ctrl-C stops the process. Listen mode never runs commands.

If no frames arrive, check **System Settings → Privacy & Security → Input Monitoring** for your terminal, then restart the process. Permission requirements can vary with macOS; this tool does not bypass them. Do not use sudo.

Disable conflicting actions in **System Settings → Trackpad → More Gestures**, including Spaces/Mission Control gestures. Also check Accessibility's three-finger dragging setting. The helper does not change your settings.

## Configure commands

```sh
swift run aerospace-gestures init # first-time setup only
swift run aerospace-gestures check
swift run aerospace-gestures run --dry-run
swift run aerospace-gestures run
```

The default path is `$XDG_CONFIG_HOME/aerospace-gestures/config.json` when `XDG_CONFIG_HOME` is an absolute nonempty path; otherwise it is `~/.config/aerospace-gestures/config.json`. Pass a path to `init`, `check`, or `run` to override it; relative paths are resolved from the current working directory. `run` and `listen` never create configuration implicitly. Use `check <path>` to validate a file without starting trackpad input.

The default init example runs `/usr/bin/osascript` to show the proven popup; child output is discarded. For a harmless command-only sample, see `config.example.json` (which uses `/bin/echo`). Successful execution appears as `Command exited with status 0`.

For AeroSpace, find its absolute path:

```sh
command -v aerospace
```

Replace a binding with your path, for example:

```json
{
  "fingers": 3,
  "direction": "left",
  "command": ["/opt/homebrew/bin/aerospace", "workspace", "next"]
}
```

Configuration:

- `fingers`: 3, 4, or 5.
- `direction`: `left`, `right`, `up`, or `down`.
- `command`: executable's absolute path followed by separate arguments. No shell expansion, pipes, or redirection. For more complex actions, invoke your own executable script.
- `threshold`: optional, defaults to `0.15`, allowed range `0.02`–`0.8`. Measured as normalized trackpad displacement, not pixels. Lower values are more sensitive.

Configuration is loaded once; restart after editing. Duplicate bindings are rejected. Only use configuration/scripts you trust: commands run with your account's permissions.

## Install the binary

```sh
swift build -c release
mkdir -p "$HOME/.local/bin"
cp -n .build/release/aerospace-gestures "$HOME/.local/bin/"
"$HOME/.local/bin/aerospace-gestures" --help
```

No login item or service is installed automatically. You can keep the process running in a terminal or explicitly enable the per-user LaunchAgent below. This repository does not publish a signed installer; the commands below build and install a local release binary. Use the stable `~/.local/bin/aerospace-gestures` path for the service. The copy commands are for first install only; use the update procedure below before replacing an existing binary.

## Optional per-user service

Build and copy the executable first; service commands never build or replace it. These copy commands are for first install only. Initialize and validate the configuration before installation:

```sh
swift build -c release
mkdir -p "$HOME/.local/bin"
cp -n .build/release/aerospace-gestures "$HOME/.local/bin/"
"$HOME/.local/bin/aerospace-gestures" init # only if your config is absent
"$HOME/.local/bin/aerospace-gestures" check
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
| Binary replacement / Input Monitoring identity | Not tested. No binary replacement or TCC change was performed. |
| Trackpad reconnect | Not tested. Current recovery is `service restart`. |
| Sleep/wake | Not tested. If input stops, current recovery is `service restart`. |

## Behavior and limits

- One action per contact sequence, rearmed after all fingers lift.
- All fingers must move in the same direction; small movements and ambiguous diagonals are ignored.
- Changing finger identities/count resets the movement origin before recognition.
- Each device has independent recognition state. Devices are enumerated at startup; restart after reconnecting a trackpad.
- Only one child command runs at a time. Gestures while busy are dropped, not queued.
- Child commands receive a termination signal after five seconds, then SIGKILL one second later if still running. Ctrl-C stops input and applies the same bounded termination to an active child before the CLI exits. This bounds the direct child, not subprocess trees; commands must not daemonize.
- No taps, holds, gesture suppression, automatic startup by default, or App Store/sandbox support.
- Private device callbacks and physical recognition have no automated hardware coverage. A three-finger popup was manually confirmed on Intel and arm64 macOS 26; other OS versions and stable TCC identity across binary replacement remain unverified.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for the canonical workflow, hooks, gate, and recovery steps.

```sh
make check
```

- `Sources/GestureCore`: deterministic swipe recognition and configuration validation.
- `Sources/GestureInfrastructure`: configuration file loading, exclusive initialization, bounded command execution and startup diagnostics, LaunchAgent lifecycle, and listener locking.
- `Sources/MultitouchBridge` and `Sources/MultitouchInput`: isolated private ABI and copied contact frames.
- `Sources/GestureCLIPolicy`: testable CLI argument/path and gesture-to-binding decisions.
- `Sources/GestureCLI`: CLI composition and event wiring; listen/dry-run are safe first steps.
- See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for dependency boundaries, configuration, and test strategy.

Manual acceptance: test each bound direction in another focused app; confirm one event per swipe, no event for two fingers/pinch, rearming after lift, and no conflicting system action. Then test with the harmless example before enabling AeroSpace commands.
