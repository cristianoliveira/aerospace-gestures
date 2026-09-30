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
- **GestureInfrastructure**: command/configuration file I/O, per-user LaunchAgent lifecycle, and a kernel advisory listener lock. It preserves literal argv execution, busy rejection, output redaction, timeout escalation, and stop behavior; default config creation uses exclusive file creation and never follows/replaces a destination symlink. LaunchAgent operations inject paths, UID, and process runner; tests use temporary homes and a fake launchctl runner.
- **GestureCLIPolicy**: pure CLI argument parsing, config path resolution, executable-path decisions, and gesture-to-binding selection. Dry-run/listen suppress executable binding selection. Tested without starting devices.
- **MultitouchBridge**: isolated reverse-engineered `MultitouchSupport` C ABI and callback lifecycle.
- **MultitouchInput**: adapts the C callback into copied `[Contact]` values. The framework owns raw callback storage; the adapter copies it before returning. Repeated start is rejected without replacing the active handler; callback work already in flight may finish after stop. Recognition state and dispatch serialization remain in the CLI's main-queue callback.
- **GestureCLI**: argument/configuration handling, executable checks, user-facing messages, per-device detector state, and lifecycle composition. It delegates gesture-to-binding decisions to `GestureCLIPolicy` and process effects to `GestureInfrastructure`; startup remains outside unit-test coverage.

## Execution flow

The CLI validates command arguments and loads configuration before starting input. Both foreground `listen`/`run` and the LaunchAgent `run` path acquire the same advisory lock before starting input: a competing foreground invocation fails before device access, while the managed process waits for the lock to avoid KeepAlive retry loops. Service commands construct a per-user GUI LaunchAgent with an absolute executable/config argv and invoke launchctl through an injected argv-based process runner.
 The input adapter copies each frame and calls the consumer; the CLI serializes processing on the main queue, updates one `SwipeDetector` per device, delegates binding selection to `GestureCLIPolicy`, and starts the runner only when execution is enabled. Signal handling stops input and waits for bounded child termination/escalation before exiting.

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

`GestureCoreTests` exercise recognition and configuration without hardware. `GestureInfrastructureTests` exercise literal argv, launch failure recovery, busy rejection, timeout and stop escalation, exclusive config-file initialization, plist ownership/rollback, launchctl failures, lifecycle idempotence, status state separation, and lock contention. Service tests use temporary homes and an injected fake process runner; they never mutate real launchd. `GestureCLIPolicyTests` exercise CLI path/argument decisions, executable validation, binding selection, and dry-run suppression without starting devices. `MultitouchInputTests` exercise adapter start failure, repeated-start preservation, and stop behavior through an injected bridge without loading private frameworks. The private ABI, callback lifecycle, physical recognition, and macOS version compatibility still require manual hardware checks; service process state never proves frame delivery. The service currently retains no logs (launchd stdout/stderr use `/dev/null`) so its log-retention bound is zero; status reports launchd's last exit status but not detailed fatal diagnostics. Signing/TCC identity across binary replacement remains unverified.
