# Architecture

## Package boundaries

```text
GestureCLI ──▶ GestureInfrastructure ──▶ GestureCore
     │
     ├───────▶ GestureCore
     ├───────▶ GestureCLIPolicy ──▶ GestureCore
     └───────▶ MultitouchInput ──▶ GestureCore
                              └──▶ MultitouchBridge (private C ABI)
GestureCore ──▶ TOMLKit ──▶ vendored toml++ 3.4.0 (C++17)
```

SwiftPM enforces these edges: `GestureCore` depends on `TOMLKit` only for decoding and validation, and remains side-effect-free; infrastructure depends on core; the C bridge is imported only by the macOS input adapter; the CLI composes the modules. `TOMLKit` vendors the MIT-licensed toml++ 3.4.0 parser and compiles it as C++17. There is no generic shared library or generalized service framework.

- **GestureCore**: immutable contact/gesture values, deterministic per-contact-sequence swipe/pinch recognition, and TOML configuration decoding/validation. It performs no process, device, filesystem, or mutable-global effects.
- **GestureInfrastructure**: command/configuration file I/O, bounded opt-in command-output capture and private service log, per-user LaunchAgent lifecycle, a kernel advisory listener lock, bounded startup diagnostics, and listener shutdown ordering. `ConfigurationReloadAdapter` resolves the source afresh, reads the candidate, and runs injected validation before it returns. Nix mode trusts only the root-owned managed plist, exact argv/marker, stable `/etc/aerospace-gestures/config.toml` symlink, and non-writable root-owned TOML target under `/nix/store`; manual mode uses its startup path. LaunchAgent operations inject paths, UID, and process runner; tests use temporary homes and a fake launchctl runner.
- **GestureCLIPolicy**: pure CLI argument parsing, config path resolution, executable-path decisions, gesture-to-binding selection, thread-safe action-pause policy, and configuration-reload policy/presentation. Reload accepts one request at a time and atomically swaps only a fully loaded/validated config; failures retain the previous snapshot. Run can pause new command launches; listen/dry-run remain non-executing and have no enable/reload control. Frame-generation tokens reject callbacks queued across a toggle or successful reload, and active devices must lift before dispatch resumes. Tested without AppKit or devices.
- **MultitouchBridge**: isolated reverse-engineered `MultitouchSupport` C ABI and callback lifecycle.
- **MultitouchInput**: adapts the C callback into copied `[Contact]` values and carries its per-device frame sequence into Swift. A wrap-aware sequence gate serializes handler delivery and rejects duplicate or older frames before they can reach the CLI; the framework owns raw callback storage, which the adapter copies before returning. Repeated start is rejected without replacing the active handler; callback work already in flight may finish after stop. Recognition state and dispatch serialization remain in the CLI's main-queue callback.
- **GestureCLI**: argument/configuration handling, executable checks, user-facing messages, per-device detector state, lifecycle composition, and the AppKit status item. Only normal `run` creates an `NSStatusItem` and uses accessory activation plus `NSApplication.run`; listen/dry-run retain the non-UI event loop. It delegates gesture/pause/reload decisions to `GestureCLIPolicy` and file/process effects to `GestureInfrastructure`; `MenuBarIcon` draws the Triple Swipe template and pause badge in code, so binary-only installs need no resource bundle. Icon rasterization is tested without a status item; AppKit status-item wiring and startup remain outside automated runtime coverage.

## Execution flow

The CLI validates command arguments and loads configuration before starting input. Both foreground `listen`/`run` and the LaunchAgent `run` path acquire the same advisory lock before starting input: a competing foreground invocation fails before device access, while the managed process waits for the lock to avoid KeepAlive retry loops. Service commands construct a per-user GUI LaunchAgent with an absolute executable/config argv and invoke launchctl through an injected argv-based process runner. Normal run's menu reload performs file I/O and executable validation off-main, then atomically activates the candidate on main; it never stops/restarts input or cancels a running command. Nix-marked runs resolve the stable managed config path from the trusted plist on every reload, while other runs keep their startup path.
The input adapter copies each frame, rejects out-of-order per-device sequence numbers, and serializes handler submission; the CLI captures a policy-generation token before queuing each accepted frame to main, drops stale tokens, updates one `GestureDetector` per device, and checks the injected `GestureActionPolicy` immediately before starting a command. Pause/resume changes the generation, drops queued work, and requires active devices to lift before new dispatch; recognition/logging continues while paused. Normal `run` owns one AppKit status item and an accessory application event loop; safe modes never construct that UI. Signal handling delegates to `ListenerShutdown`, which stops input once and waits for bounded child termination/escalation before exiting. Managed startup failures write one private, size-capped stage/category record; successful input initialization clears it. Raw errors, command arguments/output, configuration contents, and touch coordinates are excluded.

## Configuration

The default file is `$XDG_CONFIG_HOME/aerospace-gestures/config.toml` when XDG_CONFIG_HOME is nonempty and absolute; otherwise it is `~/.config/aerospace-gestures/config.toml`. `init` creates the popup example exclusively. Explicit config paths override the default; relative paths resolve against the caller's current directory. `check` validates without starting devices, and run/listen never create config implicitly. Normal run loads at startup and can reload explicitly from its active source; an invalid replacement leaves the prior immutable config in use.

Canonical schema (`threshold` defaults to `0.15`; `pinch_threshold` defaults to `0.2`):

```toml
threshold = 0.15
pinch_threshold = 0.2

[[bindings]]
fingers = 3
direction = "down"
command = ["/bin/echo", "hello"]

[[bindings]]
gesture = "pinch_in"
command = ["/bin/echo", "pinched"]
```

Swipe threshold must be finite and in `0.02...0.8`; pinch threshold must be finite and in `0.05...0.5` and represents a fraction of initial two-finger separation. Swipe finger count must be 3, 4, or 5. Pinch bindings use `gesture = "pinch_in"` or `gesture = "pinch_out"` without `fingers`/`direction`; a pinch requires both contacts to move radially and ignores baselines below `0.04` normalized units. Commands are non-empty argv arrays with an absolute executable and no NUL bytes; gesture bindings must be unique. `debug_command_output` is optional and defaults to false. The CLI additionally verifies executable permissions. Normal run reloads on request; configuration is replaced only after a complete load and executable validation. Command output is never included in completion text or startup diagnostics.

## Testing and risks

`GestureCLITests` exercise menu-bar icon rasterization, template/accessibility metadata, and an additive pause badge on a fixed-size canvas without starting an application or accessing hardware. `GestureCoreTests` exercise swipe/pinch recognition (threshold boundaries, stable IDs, radial evidence, reset behavior, and false-positive rejection) and configuration without hardware. `GestureInfrastructureTests` exercise literal argv, child-output redaction, launch failure recovery, busy rejection, timeout and stop escalation, shutdown ordering/idempotence, bounded private startup diagnostics, exclusive config-file initialization, managed reload source trust, stable-symlink target refresh, config/executable validation, plist ownership/rollback, launchctl failures, lifecycle idempotence, status state separation, and lock contention. Service tests use temporary homes and an injected fake process runner; they never mutate real launchd. `GestureCLIPolicyTests` exercise CLI path/argument decisions, executable validation, binding selection, safe-mode invariants, pause/resume and reload generations, lift-to-rearm, failed reload retention, in-flight command completion, and visible reload/menu-state projection without AppKit or devices. `MultitouchInputTests` exercise adapter start failure, repeated-start preservation, stop behavior, duplicate/out-of-order callback rejection, concurrent delivery ordering, and frame-counter wraparound through an injected bridge without loading private frameworks. The private ABI, callback lifecycle, physical recognition, and macOS version compatibility still require manual hardware checks; service process state never proves frame delivery. Pinch bindings do not suppress native macOS pinch-to-zoom, and real-trackpad delivery or interaction with system zoom remains unverified. LaunchAgent stdout/stderr use `/dev/null` (zero retained output). A single mode-0600 diagnostic record, capped at 128 bytes, retains only a fixed startup stage/category and is cleared after successful input initialization; it contains no detailed error text. Status reports that category and launchd's last exit status. Login/logout, live crash recovery, binary replacement/TCC identity, trackpad reconnect, sleep/wake, and other OS/hardware combinations remain unverified. A bounded per-user LaunchAgent menu-bar test was manually performed on macOS 26.7 arm64; the user confirmed enabled/paused labels and icon, the enabled popup, no popup while paused, a fresh popup after resume/lift, no Dock icon, and persistence with Terminal closed. The exact test job and artifacts were removed afterward, with no TCC changes. Paused-state frame logging was not directly observed because LaunchAgent stdout/stderr are discarded.
