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
cp .build/release/aerospace-gestures "$HOME/.local/bin/"
"$HOME/.local/bin/aerospace-gestures" --help
```

No login item or service is installed automatically. Keep the process running in a terminal for now.

## Behavior and limits

- One action per contact sequence, rearmed after all fingers lift.
- All fingers must move in the same direction; small movements and ambiguous diagonals are ignored.
- Changing finger identities/count resets the movement origin before recognition.
- Each device has independent recognition state. Devices are enumerated at startup; restart after reconnecting a trackpad.
- Only one child command runs at a time. Gestures while busy are dropped, not queued.
- Child commands receive a termination signal after five seconds, then SIGKILL one second later if still running. This bounds the direct child, not subprocess trees; commands must not daemonize. Ctrl-C requests child termination.
- No taps, holds, gesture suppression, automatic startup, or App Store/sandbox support.
- Private device callbacks and physical recognition have no automated hardware coverage. Startup was smoke-tested on an Intel macOS 26 host; Apple Silicon and other OS versions remain unverified.

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for the canonical workflow, hooks, gate, and recovery steps.

```sh
make check
```

- `Sources/GestureCore`: deterministic swipe recognition and configuration validation.
- `Sources/GestureInfrastructure`: configuration file loading, exclusive initialization, and bounded command execution.
- `Sources/MultitouchBridge` and `Sources/MultitouchInput`: isolated private ABI and copied contact frames.
- `Sources/GestureCLIPolicy`: testable CLI argument/path and gesture-to-binding decisions.
- `Sources/GestureCLI`: CLI composition and event wiring; listen/dry-run are safe first steps.
- See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for dependency boundaries, configuration, and test strategy.

Manual acceptance: test each bound direction in another focused app; confirm one event per swipe, no event for two fingers/pinch, rearming after lift, and no conflicting system action. Then test with the harmless example before enabling AeroSpace commands.
