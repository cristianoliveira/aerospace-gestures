# Configuration guide

Use a TOML file to map trackpad gestures to commands. Start with one harmless binding, validate the file, then test recognition before enabling commands.

This guide covers the v0.4.0 source. The v0.3.0 release does not support pinch bindings. Check `aerospace-gestures --version` and `type -a aerospace-gestures`. From a checkout, replace `aerospace-gestures` in the commands below with `swift run aerospace-gestures` to use that source.

## Contents

- [Create or locate your file](#create-or-locate-your-file)
- [Complete example](#complete-example)
- [Property reference](#property-reference)
- [TOML placement rules](#toml-placement-rules)
- [Command recipes](#command-recipes)
- [Tune sensitivity](#tune-sensitivity)
- [Validate and apply changes](#validate-and-apply-changes)
- [Debug command output](#debug-command-output)
- [Troubleshooting](#troubleshooting)

## Create or locate your file

For a first experiment:

```sh
aerospace-gestures init ./config.toml
aerospace-gestures check ./config.toml
```

`init` refuses to overwrite an existing file or symlink. It creates a three-finger-down binding that shows an “It's hooked!” dialog. The same popup is in [config.probe.toml](../config.probe.toml). No AeroSpace installation is needed.

Without a path, `aerospace-gestures init` writes to:

- `$XDG_CONFIG_HOME/aerospace-gestures/config.toml` when `XDG_CONFIG_HOME` is nonempty and absolute.
- Otherwise, `~/.config/aerospace-gestures/config.toml`.

`check` and `run` require an explicit path. Relative paths resolve from your current directory. Neither `run` nor `listen start` creates a file. For an installed service, use the config path shown by `aerospace-gestures service status`; do not assume it uses the file in your current directory. See [service setup](USAGE.md#optional-per-user-service).

## Complete example

This is a complete file with every root setting and one harmless swipe binding. Echo output is discarded unless command-output debugging is enabled; normal run still reports the command's exit status.

```toml
# Root settings must come before all binding tables.
threshold = 0.15
pinch_threshold = 0.2
debug_command_output = false

[[bindings]]
fingers = 3
direction = "left"
command = ["/bin/echo", "three-finger left"]
```

For more swipe bindings and commented opt-in pinch bindings, see [config.example.toml](../config.example.toml).

To add a pinch, append this binding to the file above:

```toml
[[bindings]]
fingers = 3
direction = "in"
command = ["/bin/echo", "three-finger pinch in"]
```

Use `direction = "out"` for a spread-out gesture. Pinch and swipe bindings can share a finger count. Native macOS pinch-to-zoom still runs, so test your own trackpad and settings before assigning important commands.

## Property reference

The file must be valid UTF-8 TOML. Names and direction values are case-sensitive. These are the supported properties; there are no per-binding sensitivity overrides.

### Root settings

| Property | Type | Default | Accepted values and meaning |
| --- | --- | --- | --- |
| `threshold` | Number | `0.15` | Finite value from `0.02` to `0.8`, inclusive. Swipe displacement in normalized trackpad coordinates, not pixels. Lower is more sensitive. |
| `pinch_threshold` | Number | `0.2` | Finite value from `0.05` to `0.5`, inclusive. Relative change in finger spread. Independent of the swipe threshold; lower is more sensitive. |
| `debug_command_output` | Boolean | `false` | `true` exposes command stdout/stderr. Use temporarily; output can contain secrets. See [output debugging](#debug-command-output). |
| `bindings` | Array of tables | Required | Define each entry with `[[bindings]]`. Use `bindings = []` for an intentional no-action file. |

An empty file is not a no-action configuration: it lacks the required `bindings` property. This is a complete no-action file:

```toml
bindings = []
```

Do not combine `bindings = []` with `[[bindings]]` tables in the same file.

### Binding properties

Every `[[bindings]]` entry requires all three properties:

| Property | Type | Accepted values and meaning |
| --- | --- | --- |
| `fingers` | Integer | Swipes: `3`, `4`, or `5`. Pinches: `2`, `3`, `4`, or `5`. |
| `direction` | String | Swipes: `"left"`, `"right"`, `"up"`, `"down"`. Pinches: `"in"` (together), `"out"` (apart). Physical finger motion, independent of Natural Scrolling. |
| `command` | Array of strings | Nonempty list: absolute executable path first, then separate arguments. No NUL bytes. The CLI checks that the executable is executable. |

A finger-count/direction pair can appear only once. Two-finger swipes are unsupported. The obsolete `gesture` property is rejected; use `fingers` and `direction` instead.

## TOML placement rules

Put all root settings **before the first `[[bindings]]`**. A blank line or comment does not end a TOML table.

Wrong: this setting belongs to the binding and does not change swipe sensitivity:

```toml
[[bindings]]
fingers = 3
direction = "left"
command = ["/bin/echo", "left"]

threshold = 0.25 # Wrong scope; not a root setting.
```

Correct:

```toml
threshold = 0.25

[[bindings]]
fingers = 3
direction = "left"
command = ["/bin/echo", "left"]
```

Unknown properties can be ignored. A successful `check` does not prove that a misspelled or misplaced setting took effect. Check spelling and scope against the reference above.

## Command recipes

Commands run with your account's permissions. Use only configuration and scripts you trust. Each array element is one literal argument: there is no shell expansion of `~`, `$HOME`, wildcards, pipes, or redirection. Spaces inside an argument do not require additional shell quotes.

For example, `command = ["/bin/echo", "$HOME"]` prints the literal text `$HOME`, not your home directory. AeroSpace's `exec-and-forget` is its own configuration directive, not an executable for this app.

### Focus AeroSpace windows

Find your executable:

```sh
command -v aerospace
```

Replace **both** executable paths below with that absolute path. This is a complete configuration:

```toml
threshold = 0.15

[[bindings]]
fingers = 3
direction = "left"
command = ["/opt/homebrew/bin/aerospace", "focus", "left"]

[[bindings]]
fingers = 3
direction = "right"
command = ["/opt/homebrew/bin/aerospace", "focus", "right"]
```

AeroSpace must be running. Test its command in your terminal before assigning it to a gesture.

### Run your own script

For shell logic, create a script with a shebang. For example, save this as `$HOME/.local/bin/gesture-action` after creating the directory with `mkdir -p "$HOME/.local/bin"`:

```sh
#!/bin/sh
set -eu
exec /usr/bin/open -a Calculator
```

Make it executable and test it with stdin closed. This test opens Calculator:

```sh
chmod +x "$HOME/.local/bin/gesture-action"
"$HOME/.local/bin/gesture-action" </dev/null
printf '%s\n' "$HOME/.local/bin/gesture-action"
```

Copy the absolute path printed by the last command into a binding. Replace `/Users/YOUR_NAME` below; do not put `$HOME` or `~` in the TOML string:

```toml
[[bindings]]
fingers = 3
direction = "down"
command = ["/Users/YOUR_NAME/.local/bin/gesture-action"]
```

Use absolute paths inside scripts too. Do not depend on an interactive shell's PATH or working directory, especially under a LaunchAgent. Child stdin is always `/dev/null`; pass `--no-stdin` if the called tool supports it.

### Fixed execution limits

These are runtime rules, **not configuration properties**:

- Only one child command runs at a time. Gestures while busy are dropped, not queued.
- After five seconds, the child receives a termination signal. If it remains alive, it receives SIGKILL one second later.
- Ctrl-C applies the same bounded shutdown to an active child.
- These limits cover the direct child, not subprocess trees. Scripts must not daemonize or leave background jobs running. Prefer `exec` for a final command.

There are no TOML timeout, queue, cooldown, or working-directory settings.

## Tune sensitivity

1. Start with the defaults in the complete example.
2. Run `aerospace-gestures check ./config.toml`.
3. Run `aerospace-gestures run ./config.toml --dry-run`. This loads your thresholds without executing commands.
4. Repeat the same gesture, lifting all fingers between attempts.
5. Press Ctrl-C. Change only one root threshold, then repeat steps 2–4. Dry-run has no reload control.

For a swipe that needs too much movement, try lowering `threshold` from `0.15` to `0.12`. For accidental swipes, try raising it to `0.2`. These are starting experiments, not hardware-calibrated recommendations. All fingers must move together; ambiguous diagonals are ignored.

For pinches, `pinch_threshold = 0.2` means a 20% change from the initial finger spread. With two fingers, spread is their distance. With three to five, it is the root-mean-square distance from their center. Lower values require less change; higher values require more.

Sensitivity is not the only condition. Both contacts in a two-finger pinch must move in opposite radial directions. All contacts in a three-to-five-finger pinch must move radially with a consistent scale. Asymmetric movement may be rejected. Initial baselines below `0.04` separation (two fingers) or `0.02` RMS radius (three to five) are ignored. Changing finger count or identities resets the movement origin.

`listen start` uses default thresholds, not your configuration file. Use it to check input delivery, not to test custom sensitivity. Only one listener can run at a time; if a service owns it, see [service troubleshooting](USAGE.md#service-troubleshooting-and-updates) before testing in the foreground.

## Validate and apply changes

| Command or control | What it proves or changes |
| --- | --- |
| `aerospace-gestures check ./config.toml` | Validates TOML, supported values, duplicate bindings, and executable permissions. Does not start input or run commands. |
| `aerospace-gestures run ./config.toml --dry-run` | Observes recognition with this file's thresholds. Never launches commands; does not prove a binding's command works. |
| `aerospace-gestures run ./config.toml` | Enables configured commands immediately. Use only after reviewing the file. |
| **Reload configuration** in the menu | Validates and applies the active file in normal run, including service runs. No automatic reload occurs when you save. |

For a safe edit cycle, choose **Disable actions**, edit the active file, run `check` against that path, then choose **Reload configuration**. Check the menu result before enabling actions again. Lift all fingers before trying a fresh gesture.

Successful reload preserves pause state and running commands, discards queued old-config frames, and requires active fingers to lift before dispatch resumes. Failed reload keeps the previous configuration and shows an error in the menu. Output-debugging changes affect future commands; a running command keeps its original output destination. Listen and dry-run have no reload control.

Foreground/manual runs reload their original config path. A Nix-managed LaunchAgent marked with `AEROSPACE_GESTURES_NIX_MANAGED=1` rereads its trusted root-owned plist and stable `/etc/aerospace-gestures/config.toml` symlink on each reload. Update and rebuild your Nix declaration, then reload; do not edit the store file. Changed-config hot reload has deterministic test coverage but remains unverified on real hardware.

## Debug command output

Set `debug_command_output = true` before all `[[bindings]]` tables, validate, and reload or restart your run. Normal foreground run forwards stdout/stderr to the matching terminal streams. By default, both are discarded and only the exit status is logged.

Managed LaunchAgents, including Nix-managed ones, append tagged output to a private log:

```sh
tail -f "$HOME/Library/Application Support/aerospace-gestures/command-output.log"
```

The file is mode `0600` and capped at 1 MiB. Raw output is capped at 64 KiB per command, plus small stream labels. Further output is drained and discarded so the child does not block. If the managed log path is unsafe or unavailable, capture is disabled and a warning goes to the macOS unified log; commands still run.

**Output can contain credentials or other sensitive data.** Disable debugging when done and reload. The log persists; to delete it:

```sh
rm "$HOME/Library/Application Support/aerospace-gestures/command-output.log"
```

## Troubleshooting

| Symptom | Next check |
| --- | --- |
| TOML parse error | Run `check` and inspect the reported line/column. Check quotes, brackets, and table placement. |
| Missing bindings | Add at least one complete `[[bindings]]` table, or use `bindings = []` for no actions. |
| Duplicate binding | Keep only one entry for each finger-count/direction pair. |
| Executable rejected | Use an absolute executable path. Check that it exists and has execute permission; use `chmod +x` for your own script. |
| Setting has no effect | Check spelling, root placement, active file path, and reload result. Restart dry-run after edits. |
| Gesture appears but no command runs | Check the matching binding, enabled/paused state, and execution mode. Listen/dry-run never execute. Busy commands cause new gestures to be dropped. |
| Command exits unsuccessfully | Test the same executable and arguments with stdin closed; temporarily enable output debugging. `check` does not validate a tool's arguments or runtime dependencies. |
| Echo produces no visible text | Enable `debug_command_output`; successful execution normally shows only `Command exited with status 0`. |
| No gesture events | Follow [input and permission checks](USAGE.md#try-safely). Config validation does not prove hardware delivery. |
| macOS also performs an action | Disable conflicting gestures in System Settings if desired. This app cannot suppress system gestures. |

For service lifecycle, permissions, and hardware limitations, continue with [Usage](USAGE.md).
