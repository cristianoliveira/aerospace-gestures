---
id: TASK-0008
title: Validate foundation and guardrails before service features
status: todo
depends_on: []
priority: high
tags: [architecture, foundation, guardrails]
---

# Validate foundation and guardrails before service features

## Problem
The new architecture and quality gate passed local checks, but no remote CI run or physical adapter regression verified them under real use. Starting service and UI features now would build on unverified boundaries.

## Outcome

We have evidence that the current boundaries and canonical gate protect the next change, plus a clear list of checks that require a human or a remote repository. This round adds no service, menu-bar, or gesture features.

## Acceptance criteria

- [ ] Review actual SwiftPM dependency boundaries, adapter callback ownership/shutdown, CLI device-free policy tests, and command execution failure coverage against the architecture document. Record any observed gap with reproduction steps; fix only proven foundation defects with focused tests.
- [ ] Re-run the canonical `make check`, hook safety/failure probes, and focused coverage on the settled tree. Confirm local and CI commands match; do not silently add format or hardware tests to the normal gate.
- [ ] Attempt remote CI only if a repository/CI target is configured and authorized. Otherwise record that remote CI was not run and its exact prerequisite; do not create a remote or push automatically.
- [ ] Record whether the three-finger popup/listen regression can be run on a real trackpad. If not available, keep physical input/private-ABI compatibility explicitly unverified and provide the human reproduction command; a passing unit test is not hardware evidence.
- [ ] Save evidence, limitations, and next-step decision in a local report. Commit any code or docs fixes with TASK-0008; close the board task only when the audit and available checks are complete.

## Non-goals

No LaunchAgent installation, service lifecycle, menu-bar UI, new gesture behavior, or speculative framework refactor.

