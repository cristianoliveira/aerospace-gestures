---
id: TASK-0006
title: Add executable quality gates and engineering guardrails
status: doing
depends_on: [TASK-0005]
priority: high
tags: [guardrails, tooling, ci]
---

## Problem

This new Swift repository has tests but no shared local/CI gate, versioned hooks, or contributor workflow. Future configuration/service work needs repeatable checks instead of prose-only expectations.

## Policy → command → enforcement

- Canonical `make check`: lint/compiler diagnostics, type/build checks, and deterministic tests only. No real device access, GUI prompts, or launchd mutations.
- Gate success stdout is exactly `true`; failure stdout begins with `false`, followed by bounded diagnostics. Preserve nonzero exit status and save full logs locally, not in git.
- Versioned pre-commit and pre-push hooks plus macOS CI call the same `make check`. A watcher, when used, calls that command too; do not invent a separate watcher gate.
- `make hooks-install` explicitly installs the versioned hooks path without silently replacing unrelated hook setup. `make hooks-check` verifies installation. Commit-msg enforces the repository's conventional commit format, including existing `plans(new)` style.
- Expose `make test` and focused-test instructions. `make format`, `make format-check`, `make coverage`, and any architecture/security analysis remain explicit checks outside the normal gate.
- Prefer existing Swift toolchain lint/format support when available. Document/pin the supported toolchain and any additional tool version; no floating third-party tool installs.
- CI must have local equivalent commands. Pin external workflow actions to immutable revisions if used.

## Workflow documentation

Create DEVELOPMENT.md as the single command path for setup, claiming a plans task, TDD, focused feedback, gate, commit, landing, and release verification. Link `docs/ARCHITECTURE.md` instead of duplicating it.

- Discover work through board; mark doing before implementation and done only after acceptance evidence and code commit.
- Use temporary homes and injected adapters; never alter real user services from automated tests.
- No implicit shell evaluation, hidden global dependencies, ignored-artifact commits, private ABI leakage into domain, or unbounded persistent logs.
- Define failure → recovery command guidance for missing Swift/tooling, gate failures, formatting, hook installation, and dependency violations.
- Define release trigger and local release verification command before creating any release workflow. Do not publish or push as a side effect of setup.
- Define objective done criteria: acceptance tests, applicable manual evidence, focused coverage/risk review, documentation, clean commit, and task-board transition.
- No third-party runtime dependencies currently; record that fact rather than adding a meaningless package audit. New dependencies require pinned resolution and a relevant audit/review.

## Acceptance criteria

- [ ] Makefile, versioned hooks, CI workflow, tool configs where applicable, and DEVELOPMENT.md exist with one canonical normal gate.
- [ ] Passing gate prints exactly `true`; controlled lint/type/test failures print `false` first and bounded diagnostics, return nonzero, and never mask failures through pipelines.
- [ ] Validate hook install/check, conventional commit acceptance/rejection, and local/CI command alignment without regex tests of documentation/config text.
- [ ] Formatter operation is explicit and does not silently rewrite source during check/commit.
- [ ] CI uses a documented macOS/Swift environment compatible with the package; hardware tests stay manual.
- [ ] Advanced checks stay outside normal gate unless separately agreed; coverage policy is risk-based and recorded rather than an arbitrary 100% target.
- [ ] Verify commands via watcher or bounded targeted checks; state any unrun CI/release/manual checks honestly.
- [ ] No automatic remote push, publication, or real service installation. Commit completed work with TASK-0006.

## Scope

Minimal Swift-native engineering guardrails. No generic workflow framework, new feature implementation, or blanket dependency/tool installation.
