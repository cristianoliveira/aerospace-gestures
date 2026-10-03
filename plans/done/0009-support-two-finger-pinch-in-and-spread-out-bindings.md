---
id: TASK-0009
title: Support two-finger pinch in and spread out bindings
status: done
depends_on: []
priority: normal
tags: []
---

# Support two-finger pinch in and spread out bindings

## Problem
People can bind commands to directional swipes but not to the familiar inward and outward two-finger pinch gestures. New recognition must avoid triggering commands from translation, rotation, or noise, while preserving existing swipes.

## Outcome and language
- **Pinch in:** two fingers move toward each other.
- **Spread out:** two fingers move apart; configuration uses `fingers = 2` and `direction = "out"`.
- A user can optionally bind one command to either discrete gesture. Nothing fires without a matching binding.

## Acceptance criteria
- [x] Stable two-finger inward/outward motion fires the matching event once per contact sequence; a full lift rearms it. A second device is independent.
- [x] Translation/swipe, rotation at near-constant separation, subthreshold jitter, incomplete one-finger movement, invalid coordinates, finger-ID/count changes, and zero/very small baseline separation do not fire. Pinch/spread must not emit a swipe for the same sequence.
- [x] Existing three-to-five-finger directional TOML configurations, recognition, and behavior remain valid. All bindings use `fingers` and `direction`: pinch uses exactly two fingers with `in`/`out`, and swipes use three to five with cardinal directions. Missing/invalid/mixed/duplicate bindings, unsupported finger counts, and the obsolete `gesture` field fail validation clearly.
- [x] A documented, bounded pinch sensitivity setting is separate from the existing swipe displacement threshold. Detection behavior is deterministic and tested at below/above threshold and reset boundaries.
- [x] Listen and dry-run never execute commands; run mode preserves pause, busy-child, reload, and per-device isolation semantics for new gestures. CLI displays understandable names.
- [x] README/Usage/Architecture describe the syntax and explicit limitation: the app does not suppress macOS pinch-to-zoom, and real-trackpad delivery/interference remains unverified until manual validation.
- [x] Implement tests first for successful and failed recognition/configuration/dispatch paths; `make check`, focused tests, and PR CI pass. Open exactly one feature PR for this plan; do not merge/tag/release as part of this plan.

## Non-goals and constraints
- No rotation, continuous zoom factor, gesture interception, default pinch bindings, new permissions, live service or configuration installation.
- Existing CommandRunner and LaunchAgent logic must remain unchanged unless a concrete integration bug demands it.
- Hardware behavior is an explicit evidence gap, not a claim of support: perform a consented real-trackpad check later before promising interaction with native macOS zoom.

## Completion evidence
- Implementation: `32e47fc` (TASK-0009); 167 tests passed locally, independent QA GO.
- PR: https://github.com/cristianoliveira/aerospace-gestures/pull/2; both initial GitHub checks passed. Physical-trackpad validation is still outstanding before relying on the feature.
