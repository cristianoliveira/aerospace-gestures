# Per-user LaunchAgent feasibility (TASK-0002)

Date: 2026-09-30. This records one bounded local test, not a service implementation.

## Result

On macOS 26.7 (arm64), the release binary started as a temporary LaunchAgent in the logged-in GUI domain. The human tester closed Terminal, performed one three-finger downward swipe, and confirmed exactly one “It's hooked!” dialog. The agent log independently recorded frame receipt, one `3-finger down` event, and successful command exit.

This is evidence for one host/session and one trackpad. It does not establish compatibility across macOS versions, users, TCC states, or future private ABI changes.

## Procedure and evidence

- The pre-existing ad-hoc listener was rechecked by UID, PID, argv, cwd, and executable. The user explicitly authorized stopping only PID 87435; it exited after SIGTERM. No other listener was stopped.
- Built natively with `arch -arm64 /usr/bin/swift build -c release -Xswiftc -warnings-as-errors`. The release executable was arm64 Mach-O, mode 755, SHA-256 `ae3e6a533156ee5dfd7575b28966455a8bcb23828f5b10fde0e043014f8fbdf6`.
- The previously absent `~/.local/bin/aerospace-gestures` slot was populated for the trial. Source and copied binary hashes and ad-hoc CodeDirectory CDHash (`9e1107c21dc0855cb0e20dde6bd212a706de5552`) matched. `codesign` reported identifier `aerospace-gestures`, no Team ID. No prior installed binary existed, so replacement/permission identity preservation against an existing installation could not be compared.
- A private temporary `XDG_CONFIG_HOME` was used. Release `init` created its default popup config there (mode 600); release `check` reported one valid binding. The user's `~/.config` was not created or changed; tracked `config.probe.json` remained unchanged.
- Temporary label `org.cristianoliveira.aerospace-gestures.task0002.20260930` was bootstrapped only into `gui/503` from a plist under a private temp directory. It used `RunAtLoad`, `KeepAlive=false`, an absolute release binary path, private XDG config, and temporary stdout/stderr paths. `launchctl print` showed `state = running`, `initialized = 1`, and one run. This alone was not treated as hardware success.
- Log sequence: `Listening`; `No frames yet`; after the human swipe, `Receiving trackpad frames`, `3-finger down`, and `Command exited with status 0`. Stderr was empty. The human confirmed the dialog appeared exactly once with Terminal closed.

## Permissions and signing

No sudo, TCC reset, permission toggle, signing operation, or system setting change occurred. No permission prompt was reported. The successful callback and popup demonstrate that this launchd instance received the tested gesture, but the existing TCC authorization source was not inspected; do not infer that Terminal and launchd share an identity. The release is ad-hoc signed without a Team ID. Byte-identical copying preserved its embedded CodeDirectory for this trial; there was no previous install at the destination to compare.

## Cleanup

The exact temporary label was booted out. A subsequent `launchctl print` reported the job absent, PID 16486 was gone, and no project listener remained. The hash-verified test copy in `~/.local/bin`, temporary plist/logs/XDG config, and test directory were removed. The personal default config remains absent. The unrelated `org.nixos.aerospace` agent was left untouched.

## Human reproduction

On a logged-in GUI session with a multitouch trackpad, build the arm64 release, install the binary at `~/.local/bin/aerospace-gestures`, run `aerospace-gestures init` once if the default config is absent, and validate the path printed by init with `aerospace-gestures check <config.toml>`. Register a temporary per-user LaunchAgent for `aerospace-gestures run <config.toml>` in `gui/$(id -u)`, then close Terminal and perform one three-finger downward swipe. Expect exactly one dialog. Confirm frame receipt and the command exit separately from the UI result. Boot out the exact temporary label and remove only test-owned files afterward.

No TASK-0003 service implementation was started. The plan card remains with the product owner for closeout.
