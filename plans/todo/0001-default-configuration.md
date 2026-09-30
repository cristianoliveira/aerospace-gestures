---
id: TASK-0001
title: Add default configuration and safe initialization
status: todo
depends_on: []
priority: high
tags: [configuration, cli]
---

## Problem

Every run requires an explicit config path. Users need a predictable location and a safe way to create the proven popup configuration.

## Approach

- Default to `$XDG_CONFIG_HOME/aerospace-gestures/config.json` when XDG_CONFIG_HOME is nonempty and absolute; otherwise `~/.config/aerospace-gestures/config.json`.
- Explicit paths take precedence; relative explicit paths resolve against the caller's working directory. Inject home/environment/current-directory providers for tests.
- Add `init`, default-path `check`, `run`, and `run --dry-run`. Preserve `listen`, `check <path>`, and `run <path> [--dry-run]`.
- Preserve JSON schema: optional threshold and bindings containing finger count, direction, executable/arguments array.
- `init` creates parent directories and the three-finger-down popup example using exclusive creation. Never overwrite a file or symlink. Run/install must not implicitly create config.
- Load config once at startup; no watcher. Service restart will apply edits.
- Root/subcommand help includes paths, prerequisites, examples, and exact recovery commands. Missing config reports its resolved path and `init` guidance.

## Acceptance criteria

- [ ] Tests first cover default/explicit precedence, empty/relative XDG fallback, spaces, relative overrides, missing/invalid config, and non-overwriting init.
- [ ] A temporary home can initialize and validate the popup binding; repeated init leaves bytes unchanged.
- [ ] `check` validates schema and executables without starting devices or executing commands.
- [ ] CLI parsing/config resolution is testable independently of multitouch startup; no unnecessary framework abstraction.
- [ ] Focused checks and changed-code coverage recorded; README updated and code committed with TASK-0001.

## Scope

No GUI, hot reload, new gesture types, system-gesture suppression, or service installation in this task.
