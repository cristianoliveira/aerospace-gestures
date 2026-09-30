---
id: TASK-0007
title: Add menu-bar enable and disable control for debugging
status: todo
depends_on: [TASK-0003]
priority: normal
tags: [macos, debugging, ui]
---

## Problem

Testing gestures currently requires terminal commands to control execution. Users need a small, visible menu-bar control to pause actions without stopping the listener or losing gesture diagnostics.

## Behavior

- Show a small macOS status-item icon while the normal gesture service runs. Use native AppKit NSStatusItem; no settings window or Dock icon.
- Menu displays current state and one Enable actions / Disable actions toggle.
- Enabled: configured gesture commands may execute.
- Disabled: continue recognition and normal bounded gesture logging, but launch no commands. Clearly label this as actions paused, not device access stopped.
- Distinguish active/paused appearance without relying only on color; provide accessible label and menu state.
- Pause is immediate for new command dispatch. It does not terminate a command already running; document this.
- Drop paused/pending gestures; never replay them on resume. After resuming, require fingers to lift before a new gesture can trigger an action.
- State is session-only for the first version: startup/restart defaults to enabled. Document this clearly; do not silently edit config or login-startup settings.
- Keep `listen` and `--dry-run` incapable of executing commands regardless of UI state. Do not add a menu action that upgrades a safe mode into command execution.

## Architecture and service integration

- Build on TASK-0003's single-instance service and stable installed executable. The menu must control that same process, not start another listener or introduce a separate IPC daemon.
- Own AppKit objects and event handling on the main thread with a proper application event loop. Keep UI code outside GestureCore and make state transitions/dispatch policy testable without AppKit or hardware.
- Serialize pause/resume and command dispatch so queued callback work cannot launch commands after pause or replay stale gestures after resume.
- Validate whether the current CLI executable with accessory activation policy is sufficient under launchd; introduce an app bundle only if the manual experiment requires it. Preserve CLI help/check/init behavior without starting an application loop.
- Keep launchd start/stop/uninstall as service lifecycle controls. Do not add a misleading Quit action that KeepAlive would immediately undo.
- Status icon indicates action policy, not proof of hardware responsiveness. If input initialization fails, do not show a healthy enabled listener; report the existing actionable error.

## Acceptance criteria

- [ ] Tests first cover enabled dispatch, paused suppression, repeated toggles, pending callbacks, no replay, lift-to-rearm, and already-running command semantics.
- [ ] Listen/dry-run remain non-executing across all supported UI transitions.
- [ ] UI logic uses injected application policy; domain remains independent of AppKit and mutable global UI state.
- [ ] Manual external-trackpad test: enabled three-finger down shows popup; paused swipe logs but shows no popup; resume plus fresh swipe shows exactly one popup.
- [ ] Menu and accessibility labels accurately show state, including after toggles; no color-only distinction.
- [ ] LaunchAgent mode shows exactly one menu-bar item with terminal closed; no Dock icon, duplicate listener, or unintended service restart on toggle.
- [ ] Restart resets to enabled as documented; service stop removes icon and service start restores it.
- [ ] Focused tests/changed-code coverage and manual OS/architecture evidence recorded. No automated tests mutate real services or require a live trackpad.
- [ ] README documents toggle semantics, logs, startup default, and distinction between pausing actions and stopping the service. Architecture doc covers AppKit ownership/event loop.
- [ ] Commit completed work with TASK-0007 and move the task to done only after acceptance evidence.

## Scope

Small debugging control only. No settings editor, per-binding switches, persistent pause preference, global shortcut, full GUI framework, or separate control process.
