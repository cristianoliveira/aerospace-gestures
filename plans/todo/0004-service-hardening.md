---
id: TASK-0004
title: Verify service reliability and document operations
status: todo
depends_on: [TASK-0003]
priority: normal
tags: [service, reliability, documentation]
---

## Problem

Successful service startup alone does not prove reliable login recovery, bounded logs, safe shutdown, or stable permissions after updates.

## Approach

- Verify bounded log retention/rotation and diagnosable fatal initialization/permission failures without rapid restart loops. Do not record command arguments or raw touch coordinates.
- Verify shutdown releases devices and handles an active child command. Keep the limitation that arbitrary descendant processes are not managed explicit.
- Test logout/login, crash recovery, config reload through restart, and permissions after binary replacement.
- Test external trackpad reconnect and sleep/wake. If restart is necessary, document the limitation and exact recovery command instead of implying automatic recovery.
- Document release installation, first popup, AeroSpace binding, XDG/default/explicit path resolution, login behavior, service troubleshooting, and uninstall.

## Acceptance criteria

- [ ] Focused deterministic tests cover added logic and failure paths; changed-code coverage recorded. No routine full CI run required.
- [ ] Child command argv remains literal; no shell evaluation or third-party dependencies added without need.
- [ ] Manual login/crash/restart/update/reconnect/sleep results include OS and architecture, with untested cases clearly marked.
- [ ] Manual registrations/processes cleaned up explicitly; unit tests never mutate real service state.
- [ ] Log retention is bounded and shutdown behavior verified.
- [ ] README distinguishes private API limitations, process health, and actual gesture responsiveness.
- [ ] Evidence report saved and completed work committed with TASK-0004.

## Out of scope

GUI, hot reload, gesture suppression, taps/holds, system-wide daemon, automatic permission changes, general command scheduling, and package distribution/signing infrastructure. Revisit signing only if TASK-0002 proves it necessary.
