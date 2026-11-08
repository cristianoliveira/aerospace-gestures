# App-specific gestures: Herdr and Brave

Use the same gesture for the same task in different apps: four-finger left
selects the next tab; four-finger right selects the previous tab. Commands
run directly, without simulated keyboard shortcuts.

Requires **v0.7.0-alpha.1**, which adds experimental app-scoped bindings.
Earlier versions do not accept `app`. Check the exact binary your listener
uses, not only the first binary on your shell's PATH.

## Prepare

1. Install the apps you want to control. The Herdr example requires the
   desktop app and its `herdr-app` CLI, not the older Herdr TUI.
2. Find your Herdr executable with `command -v herdr-app`.
3. Verify each app's bundle identifier:

   ```sh
   /usr/bin/osascript -e 'id of app "Herdr"'
   /usr/bin/osascript -e 'id of app "Brave Browser"'
   ```

   These examples use `dev.herdr.app` and `com.brave.Browser`. Matching is exact
   and case-sensitive; another browser or release channel may have a different ID.
4. Keep app-specific gestures enabled in the menu-bar control. Disabling them
   restores a matching generic binding, if one exists; it never makes an
   app-scoped command global.

Commands use literal argument arrays. Replace the example executable and
script paths below with **absolute paths** on your machine. `~`, `$HOME`,
pipes and other shell syntax are not expanded inside a binding.

## Herdr: next and previous tab

This is a complete configuration. Replace both `/absolute/path/to/herdr-app`
values with the executable path from `command -v herdr-app`.

```toml
threshold = 0.15

[[bindings]]
fingers = 4
direction = "left"
app = "dev.herdr.app"
command = ["/absolute/path/to/herdr-app", "do", "tab.next"]

[[bindings]]
fingers = 4
direction = "right"
app = "dev.herdr.app"
command = ["/absolute/path/to/herdr-app", "do", "tab.prev"]
```

No command runs for these gestures outside Herdr unless you also define a
matching generic binding. Existing three-finger desktop gestures can stay
unchanged. Directions mean physical finger movement, independent of Natural
Scrolling.

### Optional: open your picker and inbox

Herdr's `mod.open` toggles an installed mod: repeating the gesture closes it.
For a setup with personal mods named `tmux-picker` and `intray`, append:

```toml
[[bindings]]
fingers = 4
direction = "up"
app = "dev.herdr.app"
command = ["/absolute/path/to/herdr-app", "do", "mod.open", "--name", "tmux-picker"]

[[bindings]]
fingers = 4
direction = "down"
app = "dev.herdr.app"
command = ["/absolute/path/to/herdr-app", "do", "mod.open", "--name", "intray"]
```

**Those two mods are custom examples, not shipped Herdr features.** Use the
names of mods installed under your Herdr configuration's `mods/` directory.
Skip these bindings if you do not have suitable mods. `herdr-app commands`
lists built-in commands; `herdr-app status` reports mod errors. Read Herdr's
installed `~/.config/herdr-app/AGENTS.md` before creating a personal mod.

## Brave: next and previous tab

Brave exposes its active tab index through AppleScript. The
[helper script](../examples/brave-tabs.applescript) changes that index in the
front window and wraps at either end. It does not read page content or send
keyboard shortcuts. It does nothing when Brave is closed, not frontmost,
has no windows, or the front window has fewer than two tabs.

From this repository's root, copy the reviewed helper to a stable location. Its
`~/.local/share/aerospace-gestures/` directory is user data and intentionally
keeps its legacy name after the executable is renamed to `cafune`:

```sh
install -d "$HOME/.local/share/aerospace-gestures"
install -m 644 examples/brave-tabs.applescript \
  "$HOME/.local/share/aerospace-gestures/brave-tabs.applescript"
printf '%s\n' "$HOME/.local/share/aerospace-gestures/brave-tabs.applescript"
```

The helper is passed to `/usr/bin/osascript`, so it does not need executable
permission. Replace both `/Users/YOUR_NAME/...` paths with the absolute path
printed above, then append these bindings to the Herdr configuration, or use
them alone as a complete configuration:

```toml
[[bindings]]
fingers = 4
direction = "left"
app = "com.brave.Browser"
command = ["/usr/bin/osascript", "/Users/YOUR_NAME/.local/share/aerospace-gestures/brave-tabs.applescript", "next"]

[[bindings]]
fingers = 4
direction = "right"
app = "com.brave.Browser"
command = ["/usr/bin/osascript", "/Users/YOUR_NAME/.local/share/aerospace-gestures/brave-tabs.applescript", "prev"]
```

macOS may request **Automation** permission when the command first controls
Brave. Allow the request for the responsible process shown by macOS, then
retry the gesture after lifting all fingers. A first command can time out
while the permission dialog is open. Review permissions under **System
Settings → Privacy & Security → Automation** if access was denied. This is
separate from Input Monitoring used to receive gestures.

These bindings select tabs; they do not reorder, close or create tabs.
AppleScript support for other browsers differs: changing only the bundle ID
is not enough to promise compatibility.

## Keep a desktop fallback

A generic binding can coexist with both app-specific bindings for the same
gesture. For example, append this to focus an AeroSpace window when neither
Herdr nor Brave is frontmost:

```toml
[[bindings]]
fingers = 4
direction = "left"
command = ["/absolute/path/to/aerospace", "focus", "right"]

[[bindings]]
fingers = 4
direction = "right"
command = ["/absolute/path/to/aerospace", "focus", "left"]
```

Replace both AeroSpace paths using `command -v aerospace`. Scoped matches win
only for the same finger count, direction and exact modifier set. If you
already have these generic bindings, keep them instead of adding duplicates.
AeroSpace is optional for the app-only examples.

## Validate and try

1. Merge only the bindings you want into your active config. Keep root settings
   such as `threshold` before the first `[[bindings]]` table.
2. Run `cafune check /absolute/path/to/config.toml` with the same
   executable version as your listener. This validates the config and executable
   paths, not Herdr arguments, script paths, Automation access or hardware input.
3. Follow the [safe reload steps](CONFIGURATION.md#validate-and-apply-changes).
   Do not start a second listener alongside an installed service. For Nix-managed
   installs, edit your declaration and rebuild rather than editing store files.
4. Foreground Herdr or a Brave window with multiple tabs. Swipe four fingers
   left and right, lifting all fingers between attempts. Try another app to
   confirm your generic fallback still works.

The Brave helper deliberately ignores background windows: running it from a
foreground terminal is not a tab-navigation smoke test. Its index calculation
and argument validation can be tested without changing any browser windows:

```sh
# Requires macOS, installed Brave (its scripting dictionary), and Python 3.
python3 -m unittest discover -s examples/tests -v
```

For command failures, temporarily enable
[command-output debugging](CONFIGURATION.md#debug-command-output). Logs can
contain sensitive data; disable debugging after diagnosis. Automated helper
tests do not prove trackpad delivery or Automation access from a LaunchAgent.
