# Configuration and background service plan

Status: planned, not implemented.

## Goal

Run a small gesture helper at login, with user-owned configuration and predictable lifecycle commands. No GUI, sudo, or system daemon.

Evidence: user confirmed three-finger down shows the popup on an external trackpad. This proves the foreground/background-terminal launch path, not LaunchAgent access.

## User interface

```sh
aerospace-gestures init
aerospace-gestures check
aerospace-gestures run --dry-run
aerospace-gestures run

aerospace-gestures service install
aerospace-gestures service status
aerospace-gestures service stop
aerospace-gestures service start
aerospace-gestures service restart
aerospace-gestures service uninstall
```

Keep `listen`, `check <path>`, and `run <path> [--dry-run]`. Root and subcommand help must expose prerequisites, paths, examples, and recovery commands.

## Decisions

### Configuration

- Default: `$XDG_CONFIG_HOME/aerospace-gestures/config.json` when XDG_CONFIG_HOME is nonempty and absolute; otherwise `~/.config/aerospace-gestures/config.json`.
- Resolve home through an injected home-directory provider, not string replacement.
- Explicit CLI config path wins over the default. Relative explicit paths resolve against the caller's working directory.
- Preserve current JSON schema: optional threshold, bindings with fingers, direction, and executable/arguments array.
- `init` creates parent directories and the proven three-finger-down popup config. Use exclusive creation; never overwrite an existing file, including a symlink. No implicit config creation during run or installation.
- `check` validates schema and executable paths without starting devices or running actions.
- Missing config reports its resolved path and the exact `init` command.
- Read once at startup. Apply edits with `service restart`. No watcher yet.

### Installed service

- Use a per-user LaunchAgent in the `gui/<uid>` domain.
- Label: `com.aerospace-gestures`.
- Plist: `~/Library/LaunchAgents/com.aerospace-gestures.plist`.
- Stable executable: `~/.local/bin/aerospace-gestures`; build/copy explicitly before service installation. Never register `.build/debug` or another temporary binary.
- `service install` validates config and stable binary before changing launchd state. It does not build software or grant permissions.
- Serialize the plist with Foundation's property-list encoder, never shell/XML interpolation.
- Store absolute executable and resolved config paths in `ProgramArguments`. Capture the install-time XDG choice; launchd does not inherit the terminal environment. Reinstall to change the config location.
- Set an explicit working directory (user home). Explain that commands must not depend on interactive shell PATH or startup files.
- Start at login and restart on unexpected failure, with throttling to limit crash loops. Explicit stop must unload the job rather than trigger automatic restart.
- Proposed logs: `~/Library/Logs/aerospace-gestures/`. Define bounded retention/rotation before enabling persistent logging. Do not log command arguments or raw touch coordinates.
- Treat launchd-loaded, process-running, and trackpad-responsive as different states. A PID does not prove gesture access.

### Lifecycle semantics

| Command | Behavior |
| --- | --- |
| install | Register and start; enable login startup. Repeated install safely updates only our own registration. |
| status | Report installed/loaded/running state, PID and last exit status when available, config and log paths. No state changes. |
| stop | Boot out current job. Keep plist: starts again at next login. Explain this distinction in help. |
| start | Bootstrap installed plist; already running is a successful no-op. |
| restart | Stop then start to reload configuration; validate config before disrupting a working process. |
| uninstall | Stop and remove only the owned plist. Preserve binary, config, and logs. Missing installation is a successful no-op. |

Use `launchctl bootstrap`, `bootout`, and `print` via explicit argv, not a shell. Capture stderr and distinguish expected absent/already-loaded states from actual errors. Do not silently replace an unrelated plist at the chosen path. Preserve or roll back the previous working installation if update/bootstrap fails.

## Delivery sequence

### 1. Default configuration and initialization

Tests first for path precedence, empty/relative XDG fallback, paths with spaces, explicit overrides, missing config, invalid config, and non-overwriting initialization. Extract CLI parsing/config resolution only as needed; keep framework startup outside testable command handling.

Deliver `init`, optional config paths for `run`/`check`, and help. Success: a clean temporary home can initialize and validate the popup binding; repeated init leaves bytes unchanged.

### 2. LaunchAgent feasibility gate

Build and install a stable release binary. Using a temporary test LaunchAgent and the popup config, verify three-finger down with the terminal closed. Clean up the test registration afterward.

Stop the earlier ad-hoc listener before testing to avoid double actions. Record macOS version, architecture, permission requirements, and whether the permission identity survives binary replacement. Do not assume terminal Input Monitoring authorization transfers to a LaunchAgent or that signing is unnecessary.

Success: the user sees exactly one popup from an external trackpad with no terminal-hosted helper. If this fails, investigate permissions/signing/private API restrictions before implementing the rest of the service interface.

### 3. Service lifecycle commands

Separate plist construction and lifecycle decisions from filesystem/process calls. Inject the process runner, filesystem paths, and user ID for deterministic tests. Avoid a generic service framework.

Cover install/start/stop/restart/status/uninstall, repeated operations, missing binary/config, malformed or foreign plist, failed launchctl calls, failed update rollback, and preservation of user config. Decode generated plists in tests; do not regex-match XML or help text.

Add a per-user single-instance lock before listening, shared by manual runs and service runs; do not kill arbitrary matching PIDs. Cover lock contention and release. This prevents duplicate actions from two copies without stale PID-file assumptions.

Success: foreground and service copies cannot both listen; stop stays stopped during this login; start restores operation; uninstall leaves config intact.

### 4. Operational hardening and documentation

Bound persistent logs and make fatal initialization/permission failures diagnosable without a rapid restart loop. Verify graceful shutdown releases devices and handles a running child command. Explicitly retain the current limitation that arbitrary descendant processes are not managed.

Test logout/login, crash recovery, config restart, and permissions after a binary update. Test external trackpad disconnect/reconnect and sleep/wake; if restart is required, document it and provide the exact command rather than implying automatic recovery.

Document release install, first-run popup, AeroSpace binding, config path resolution, login behavior, service troubleshooting, and uninstall. Keep system-gesture suppression outside scope.

## Verification and risk gate

- Run focused unit/integration tests per change and measure changed-code coverage; no routine full CI runs.
- Local tests use temporary homes and fake launchctl; never alter the real user's registration as a unit-test side effect.
- Manual service tests must be explicit and clean up their registration/processes.
- Test command argv preservation and all failure paths; no shell evaluation or third-party dependencies needed.
- Highest risk remains the private multitouch ABI and permission identity under launchd. No success claim until the manual gate passes.
- Before each completed implementation increment: update docs, write a local evidence report, and commit.

## Out of scope

GUI, hot reload, gesture suppression, taps/holds, system-wide daemon, automatic permission changes, package distribution/signing infrastructure, and a general command scheduler. Revisit signing only if the feasibility gate requires it.

## First next step

Implement phase 1 only. Then prove the LaunchAgent path before expanding service management.
