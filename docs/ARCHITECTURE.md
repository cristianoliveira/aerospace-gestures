# Architecture

## Package boundaries

```text
GestureCLI ──▶ GestureInfrastructure ──▶ GestureCore
     │
     ├───────▶ GestureCore
     ├───────▶ GestureCLIPolicy ──▶ GestureCore
     └───────▶ MultitouchInput ──▶ GestureCore
                              └──▶ MultitouchBridge (private C ABI)
```

SwiftPM enforces these edges: `GestureCore` has no target dependencies; infrastructure depends only on core; the C bridge is imported only by the macOS input adapter; the CLI composes the modules. There is no generic shared library or generalized service framework.

- **GestureCore**: immutable contact/gesture values, deterministic swipe recognition, and JSON configuration decoding/validation. It performs no process, device, filesystem, or mutable-global effects.
- **GestureInfrastructure**: command/configuration file I/O, per-user LaunchAgent lifecycle, a kernel advisory listener lock, bounded startup diagnostics, and listener shutdown ordering. It preserves literal argv execution, busy rejection, output redaction, timeout escalation, and stop behavior; default config creation uses exclusive file creation and never follows/replaces a destination symlink. LaunchAgent operations inject paths, UID, and process runner; tests use temporary homes and a fake launchctl runner.
- **GestureCLIPolicy**: pure CLI argument parsing, config path resolution, executable-path decisions, gesture-to-binding selection, and thread-safe action-pause policy/presentation projection. Run can pause new command launches; listen/dry-run remain non-executing and have no enable control. Frame-generation tokens reject callbacks queued across a toggle, and active devices must lift before dispatch resumes. Tested without AppKit or devices.
- **MultitouchBridge**: isolated reverse-engineered `MultitouchSupport` C ABI and callback lifecycle.
- **MultitouchInput**: adapts the C callback into copied `[Contact]` values and carries its per-device frame sequence into Swift. A wrap-aware sequence gate serializes handler delivery and rejects duplicate or older frames before they can reach the CLI; the framework owns raw callback storage, which the adapter copies before returning. Repeated start is rejected without replacing the active handler; callback work already in flight may finish after stop. Recognition state and dispatch serialization remain in the CLI's main-queue callback.
- **GestureCLI**: argument/configuration handling, executable checks, user-facing messages, per-device detector state, lifecycle composition, and the AppKit status item. Only normal `run` creates an `NSStatusItem` and uses accessory activation plus `NSApplication.run`; listen/dry-run retain the non-UI event loop. It delegates gesture/pause decisions to `GestureCLIPolicy` and process effects to `GestureInfrastructure`; UI and startup remain outside automated runtime coverage.

## Execution flow

The CLI validates command arguments and loads configuration before starting input. Both foreground `listen`/`run` and the LaunchAgent `run` path acquire the same advisory lock before starting input: a competing foreground invocation fails before device access, while the managed process waits for the lock to avoid KeepAlive retry loops. Service commands construct a per-user GUI LaunchAgent with an absolute executable/config argv and invoke launchctl through an injected argv-based process runner.
 The input adapter copies each frame, rejects out-of-order per-device sequence numbers, and serializes handler submission; the CLI captures a policy-generation token before queuing each accepted frame to main, drops stale tokens, updates one `SwipeDetector` per device, and checks the injected `GestureActionPolicy` immediately before starting a command. Pause/resume changes the generation, drops queued work, and requires active devices to lift before new dispatch; recognition/logging continues while paused. Normal `run` owns one AppKit status item and an accessory application event loop; safe modes never construct that UI. Signal handling delegates to `ListenerShutdown`, which stops input once and waits for bounded child termination/escalation before exiting. Managed startup failures write one private, size-capped stage/category record; successful input initialization clears it. Raw errors, command arguments/output, configuration contents, and touch coordinates are excluded.

## Configuration

The default file is `$XDG_CONFIG_HOME/aerospace-gestures/config.json` when XDG_CONFIG_HOME is nonempty and absolute; otherwise it is `~/.config/aerospace-gestures/config.json`. `init` creates the popup example exclusively. Explicit config paths override the default; relative paths resolve against the caller's current directory. `check` validates without starting devices, and run/listen never create config implicitly.

Canonical schema (threshold is optional; default `0.15`):

```json
{
  "threshold": 0.15,
  "bindings": [
    { "fingers": 3, "direction": "down", "command": ["/bin/echo", "hello"] }
  ]
}
```

Threshold must be finite and in `0.02...0.8`; finger count must be 3, 4, or 5; commands are non-empty argv arrays with an absolute executable and no NUL bytes; gesture bindings must be unique. The CLI additionally verifies executable permissions. Configuration is loaded once.

## Testing and risks

`GestureCoreTests` exercise recognition and configuration without hardware. `GestureInfrastructureTests` exercise literal argv, child-output redaction, launch failure recovery, busy rejection, timeout and stop escalation, shutdown ordering/idempotence, bounded private startup diagnostics, exclusive config-file initialization, plist ownership/rollback, launchctl failures, lifecycle idempotence, status state separation, and lock contention. Service tests use temporary homes and an injected fake process runner; they never mutate real launchd. `GestureCLIPolicyTests` exercise CLI path/argument decisions, executable validation, binding selection, safe-mode invariants, pause/resume generations, lift-to-rearm, already-running command completion, and accessible menu-state projection without AppKit or devices. `MultitouchInputTests` exercise adapter start failure, repeated-start preservation, stop behavior, duplicate/out-of-order callback rejection, concurrent delivery ordering, and frame-counter wraparound through an injected bridge without loading private frameworks. The private ABI, callback lifecycle, physical recognition, and macOS version compatibility still require manual hardware checks; service process state never proves frame delivery. LaunchAgent stdout/stderr use `/dev/null` (zero retained output). A single mode-0600 diagnostic record, capped at 128 bytes, retains only a fixed startup stage/category and is cleared after successful input initialization; it contains no detailed error text. Status reports that category and launchd's last exit status. Login/logout, live crash recovery, binary replacement/TCC identity, trackpad reconnect, sleep/wake, and other OS/hardware combinations remain unverified. A bounded per-user LaunchAgent menu-bar test was manually performed on macOS 26.7 arm64; the user confirmed enabled/paused labels and icon, the enabled popup, no popup while paused, a fresh popup after resume/lift, no Dock icon, and persistence with Terminal closed. The exact test job and artifacts were removed afterward, with no TCC changes. Paused-state frame logging was not directly observed because LaunchAgent stdout/stderr are discarded.
