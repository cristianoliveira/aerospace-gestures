---
id: TASK-0003
title: Add per-user service lifecycle commands
status: todo
depends_on: [TASK-0002]
priority: normal
tags: [macos, service, cli]
---

## Problem

Users need login startup and predictable start/stop/update behavior without hand-editing launchd files or accidentally running duplicate listeners.

## Interface

| Command prefix: `aerospace-gestures service` | Behavior |
| --- | --- |
| install | Validate, register, and start; enable login startup. Repeated install safely updates only our registration. |
| status | Report installed/loaded/running state, PID and last exit status when available, config/log paths. No mutation. |
| stop | Boot out the current job; retain plist so it starts again next login. |
| start | Bootstrap installed plist; already running is a successful no-op. |
| restart | Validate config before stopping, then start to reload it. |
| uninstall | Stop and remove only the owned plist. Preserve binary, config, and logs. Missing installation is a successful no-op. |

## Decisions

- Per-user GUI LaunchAgent; label `com.aerospace-gestures`; plist `~/Library/LaunchAgents/com.aerospace-gestures.plist`.
- Stable executable `~/.local/bin/aerospace-gestures`. Install validates it and the config before mutation; does not build software or grant permissions.
- Encode plist through Foundation, not XML/string interpolation. ProgramArguments contains absolute executable and resolved config paths.
- Capture install-time XDG choice; launchd does not inherit terminal environment. Reinstall to change config location. Working directory is user home; commands must not rely on interactive shell startup/PATH.
- Login startup and restart on unexpected failure, with throttling. Explicit stop unloads rather than triggering restart.
- Use `launchctl bootstrap`, `bootout`, and `print` through argv. Capture stderr; distinguish absent/already-loaded states from real failures.
- Reject foreign/malformed existing plists rather than silently replacing them. Preserve or roll back a working installation on update/bootstrap failure.
- Add a per-user single-instance lock shared by manual/service listeners. Avoid stale PID-file assumptions and arbitrary PID killing.
- Proposed logs: `~/Library/Logs/aerospace-gestures/`. Define a bounded retention strategy before enabling persistent logging; never record arguments or raw coordinates.

## Acceptance criteria

- [ ] Tests first cover each lifecycle command, repeated operations, missing config/binary, foreign/malformed plist, launchctl failures, update rollback, and config preservation.
- [ ] Plist tests decode structured data, not regex-match XML/help text.
- [ ] Process runner, filesystem paths, and UID are injected; unit tests use temporary homes/fake launchctl and never mutate the real registration.
- [ ] Lock contention/release tested; foreground and service copies cannot both listen.
- [ ] Stop remains stopped for this login; start restores operation; uninstall preserves user data.
- [ ] Status distinguishes registration, process state, and unverified trackpad responsiveness.
- [ ] Root/subcommand help documents prerequisites, paths, lifecycle semantics, and recovery commands.
- [ ] Focused checks/coverage and manual lifecycle evidence recorded; code committed with TASK-0003.

## Design constraint

Separate plist/lifecycle decisions from infrastructure; do not create a generic service framework. No system daemon or sudo.
