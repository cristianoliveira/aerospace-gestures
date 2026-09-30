---
id: TASK-0005
title: Establish small Swift architecture boundaries
status: doing
depends_on: []
priority: high
tags: [architecture, foundation]
---

## Problem

Before adding configuration and launchd behavior, existing responsibilities need clear homes. GestureCore currently includes Process/Darwin command execution, and main.swift combines argument parsing, configuration loading, device callbacks, and lifecycle wiring. Adding features directly here would couple policy to macOS details and make tests harder.

## Architecture direction

Use SwiftPM targets as real compile-time boundaries, not a large layered framework:

- `GestureCore` (domain): contacts, gestures, recognition state, binding/configuration value validation. No Process, Darwin, launchctl, device access, filesystem reads, or mutable global state. Foundation value decoding is acceptable; purity is about effects, not banning standard-library modules.
- `GestureInfrastructure` (infra): command execution and, when implemented, configuration storage, instance locking, and LaunchAgent integration. Move existing CommandRunner here. Depends on domain, never the CLI.
- `MultitouchBridge` (infra): keep the private C ABI isolated. Swift adapter copies callback-owned data and hands immutable frames to the consumer. Do not leak private structs into domain.
- `GestureCLI` (cli/composition root): argument handling, wiring, exit codes, user-facing output. Keep effectful startup separate from testable command decisions; extract only what existing tests/features need.
- Fixtures stay next to the consuming tests. Do not add an empty shared `lib` target; add shared code only after a concrete second consumer appears.

Dependency direction: CLI → infrastructure/domain; infrastructure → domain; domain never → infrastructure/CLI. Keep the private C bridge reachable only through the macOS input adapter. No generic event bus, DI container, service framework, or speculative application layers.

For SwiftPM test discovery, retain standard Tests/<Target>Tests placement unless a verified package layout provides equally simple local test colocation. Do not fight the build tool merely for folder symmetry.

## Approach

- Characterize current behavior first: one event per contact sequence, direction/count, explicit argv execution, busy rejection, timeout, and configuration rejection.
- Separate command execution from domain without changing behavior. Preserve configuration schema and CLI commands.
- Make effect boundaries explicit through constructor/function injection. Introduce consumer-owned protocols only for actual integrations needing multiple implementations or fakes.
- Define callback/thread ownership and shutdown responsibilities. Recognition state must be serialized and deterministic.
- Write `docs/ARCHITECTURE.md`: actual target graph, responsibilities, execution flow, effect boundaries, testing strategy, private API risks, and canonical JSON configuration. Distinguish implemented behavior from planned default-path/service behavior.
- Use SwiftPM dependency declarations to enforce module direction. Add a separate architecture checker only if those boundaries prove insufficient; avoid custom regex source scanners.

## Acceptance criteria

- [ ] Domain has no process/device/filesystem effects; command runner tests move with its infrastructure implementation.
- [ ] Existing targeted behavior tests pass without requiring live hardware or invoking launchctl.
- [ ] CLI remains thin enough that command decisions can be tested without starting devices.
- [ ] Public APIs and injection seams are minimal and justified by an existing consumer/test.
- [ ] Package graph documents and enforces allowed dependencies. Any added boundary checker is proven with a temporary forbidden-import probe, then the probe is removed.
- [ ] Focused tests, changed-code coverage, and regression risks are recorded; no private-API compatibility claim from unit tests alone.
- [ ] Architecture document matches actual files; code committed with TASK-0005.

## Scope

Behavior-preserving architecture baseline only. Do not implement default configuration, launchd commands, or extra gesture features here. The proven external-trackpad popup remains the manual regression check.
