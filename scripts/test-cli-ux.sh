#!/usr/bin/env bash
# Behavioral CLI UX checks against the real built binary: version/help go to
# stdout with exit 0; errors go to stderr with a nonzero exit. No devices,
# no services, no installs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

swift build >/dev/null 2>&1
bin="$(swift build --show-bin-path)/aerospace-gestures"
version="$(sed -n 's/^  public static let current = "\(.*\)"/\1/p' \
  "$root/Sources/GestureCLIPolicy/CLIVersion.swift")"

failures=0
expect_stdout() { # description expected_substring command...
  local description=$1 expected=$2
  shift 2
  local out status
  out="$("$@" 2>/dev/null)" && status=0 || status=$?
  if [[ $status -ne 0 || $out != *"$expected"* ]]; then
    printf 'FAIL: %s (status %s)\n' "$description" "$status"
    failures=$((failures + 1))
  else
    printf 'ok: %s\n' "$description"
  fi
}

expect_error() { # description expected_stderr_substring command...
  local description=$1 expected=$2
  shift 2
  local err status
  err="$("$@" 2>&1 >/dev/null)" && status=0 || status=$?
  if [[ $status -eq 0 || $err != *"$expected"* ]]; then
    printf 'FAIL: %s (status %s, stderr %q)\n' "$description" "$status" "$err"
    failures=$((failures + 1))
  else
    printf 'ok: %s\n' "$description"
  fi
}

expect_stdout "--version prints the baked version on stdout" "$version" "$bin" --version
expect_stdout "version subcommand prints the baked version on stdout" "$version" "$bin" version

expect_stdout "root --help shows structured sections on stdout" "Available Commands:" "$bin" --help
expect_stdout "root help includes flags and examples" "Examples:" "$bin" --help
expect_stdout "help check shows per-command usage on stdout" "Usage: aerospace-gestures check" "$bin" help check
expect_stdout "help service lists service actions" "Actions:" "$bin" help service

expect_error "unknown command fails on stderr with available commands" "Available commands" "$bin" bogus
expect_error "unknown command with a flag still fails" "Unknown command" "$bin" bogus --version
expect_error "unknown option is not treated as a config path" "Unknown option '--dry-run' for check" "$bin" check --dry-run
expect_error "unknown short option is rejected for init" "Unknown option '-x' for init" "$bin" init -x
expect_error "service rejects unknown options" "Unknown option '--quiet' for service" "$bin" service --quiet

if ((failures)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
printf 'all CLI UX checks passed\n'
