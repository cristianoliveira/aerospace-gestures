---
id: TASK-0009
title: Support two-to-five-finger pinch in and spread out bindings
status: done
depends_on: []
priority: normal
tags: []
---

# Support two-to-five-finger pinch in and spread out bindings

## Problem
People can bind commands to three-to-five-finger directional swipes, but the open pinch PR only recognizes two fingers. Users also want three- and four-finger pinches; adding them must not misclassify swipes, rotation, or noise. Extend the same PR, with five fingers included where the same evidence and detector support it.

## Outcome and language
- **Pinch in:** the contact group contracts toward its shared center.
- **Spread out:** the contact group expands away from its shared center.
- Any supported count (2–5) can bind `direction = "in"` or `"out"` alongside its `fingers` property. No command runs without a matching binding.

## Acceptance criteria
- [x] Stable inward/outward motion with 2, 3, 4, or 5 contacts fires only the exact-count matching binding, once per contact sequence; full lift rearms it. Device state remains independent.
- [x] Group translation/swipe, rotation at near-constant spread, subthreshold jitter, one moving finger/outlier, invalid coordinates, ID/count changes, and degenerate clustered baselines do not fire a pinch. A movement must not dispatch both pinch and swipe.
- [x] Existing three-to-five-finger swipe TOML and recognition remain valid, including when a pinch binding has the same count. All bindings retain `fingers` + `direction`; unsupported counts, duplicates, old `gesture` key, and invalid combinations fail clearly.
- [x] Separate documented `pinch_threshold` retains bounded, ratio-based semantics; tests cover below/above threshold for 2–5 contacts and one-shot/full-lift reset.
- [x] Listen/dry-run do not execute commands; normal mode retains pause, busy-child, reload and per-device isolation semantics. CLI renders the correct finger count and action name.
- [x] README, Usage, Architecture, CLI help, and completed plan describe multi-finger syntax and explain that native macOS gesture interactions and real-trackpad delivery remain unverified.
- [x] Tests first for recognition/config/dispatch success and failure; `make check`, focused tests, independent QA and PR CI pass. Keep exactly one feature PR for TASK-0009; do not merge/tag/release.

## Non-goals and constraints
- No rotation, continuous zoom factor, gesture interception, default pinch bindings, new permissions, live service or configuration installation.
- Existing CommandRunner and LaunchAgent logic must remain unchanged unless a concrete integration bug demands it.
- Hardware behavior is an explicit evidence gap, not a claim of support: perform a consented real-trackpad check later before promising interaction with native macOS zoom.

## Completion evidence
- Previous two-finger implementation: `32e47fc`; consistent config naming: `c61f372`. Both iterations passed local checks and GitHub CI.
- Scope extended before merge to 2–5 fingers in the same PR: https://github.com/cristianoliveira/aerospace-gestures/pull/2. Implementation `866c31d`, adversarial regression tests `52551a0`; 175 local tests and independent QA passed, as did both initial updated PR checks. Physical-trackpad validation remains outstanding.
