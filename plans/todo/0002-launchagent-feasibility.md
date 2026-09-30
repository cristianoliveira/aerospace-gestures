---
id: TASK-0002
title: Prove gesture capture through a LaunchAgent
status: todo
depends_on: [TASK-0001]
priority: high
tags: [macos, service, feasibility]
---

## Problem

The user confirmed three-finger down shows a popup on an external trackpad, but only with the terminal-launched helper. This does not prove launchd gesture access or permission identity.

## Approach

- Explicitly build/copy a release binary to `~/.local/bin/aerospace-gestures`; never register `.build/debug` or another temporary executable.
- Use a temporary per-user LaunchAgent in `gui/<uid>` and the default popup config. No sudo, system daemon, or automatic permission changes.
- Stop the earlier ad-hoc listener before testing to prevent duplicate actions; identify it rather than killing arbitrary matching PIDs.
- Verify the popup with the terminal closed. Record OS version, architecture, required permissions, and whether binary replacement preserves permission identity.
- Do not assume terminal Input Monitoring authorization transfers to launchd or that signing is unnecessary.
- Clean up the temporary registration/process afterward.

## Acceptance criteria

- [ ] User sees exactly one popup per three-finger-down swipe on the external trackpad, without a terminal-hosted helper.
- [ ] Startup, gesture access, permission requirements, and binary replacement results are recorded separately; a PID is not treated as hardware success.
- [ ] Temporary registration/process is cleaned up without deleting user config.
- [ ] If blocked, document evidence and investigate permissions/signing/private ABI restrictions before marking done or implementing TASK-0003.
- [ ] Evidence and reproduction steps saved; completed work committed with TASK-0002.

## Risk gate

Private MultitouchSupport ABI remains unsupported. Signing infrastructure is outside scope unless this experiment proves it necessary. Manual success, not process startup alone, unlocks service implementation.
