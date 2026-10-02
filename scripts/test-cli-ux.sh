#!/usr/bin/env bash
# Behavioral CLI UX checks against the real built binary: version/help go to
# stdout with exit 0; errors go to stderr with a nonzero exit. No devices,
# no services, no installs.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_tmp="$(mktemp -d)"
trap 'rm -rf "$test_tmp"' EXIT
cd "$root"

swift build >/dev/null 2>&1
bin="$(swift build --show-bin-path)/aerospace-gestures"
# Independent expected version for the planned v0.3.0 release. The release
# workflow also checks the packaged binary against the pushed tag.
version="0.3.0"

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

expect_exact_stdout() { # description exact_stdout command...
  local description=$1 expected=$2
  shift 2
  local err_file out err status
  err_file="$(mktemp)"
  out="$("$@" 2>"$err_file")" && status=0 || status=$?
  err="$(<"$err_file")"
  rm -f "$err_file"
  if [[ $status -ne 0 || "$out" != "$expected" || -n "$err" ]]; then
    printf 'FAIL: %s (status %s, stdout %q, stderr %q)\n' "$description" "$status" "$out" "$err"
    failures=$((failures + 1))
  else
    printf 'ok: %s\n' "$description"
  fi
}

expect_usage_failure() { # description expected_help command...
  local description=$1 expected=$2
  shift 2
  local err_file out err status
  err_file="$(mktemp)"
  out="$("$@" 2>"$err_file")" && status=0 || status=$?
  err="$(<"$err_file")"
  rm -f "$err_file"
  if [[ $status -eq 0 || -n "$out" || "$err" != "$expected" ]]; then
    printf 'FAIL: %s (status %s, stdout %q, stderr %q)\n' "$description" "$status" "$out" "$err"
    failures=$((failures + 1))
  else
    printf 'ok: %s\n' "$description"
  fi
}

expect_exact_stdout "--version prints the exact baked version" "$version" "$bin" --version
expect_exact_stdout "-v prints the exact baked version" "$version" "$bin" -v
expect_exact_stdout "version subcommand prints the exact baked version" "$version" "$bin" version

expect_stdout "root --help shows structured sections on stdout" "Available Commands:" "$bin" --help
expect_stdout "root help includes flags and examples" "Examples:" "$bin" --help
expect_stdout "help check shows per-command usage on stdout" "Usage: aerospace-gestures check" "$bin" help check
expect_stdout "help listen documents explicit start action" "Usage: aerospace-gestures listen <start>" "$bin" help listen
expect_stdout "help service lists service actions" "Actions:" "$bin" help service
expect_stdout "help version is navigable" "Usage: aerospace-gestures version" "$bin" help version
expect_stdout "version --help is navigable" "Usage: aerospace-gestures version" "$bin" version --help
expect_stdout "help help is navigable" "Usage: aerospace-gestures help" "$bin" help help
expect_stdout "help --help is navigable" "Usage: aerospace-gestures help" "$bin" help --help
expect_stdout "service action help returns safe group help" "Actions:" "$bin" service status --help

root_help="$("$bin" --help)"
init_help="$("$bin" init --help)"
check_help="$("$bin" check --help)"
run_help="$("$bin" run --help)"
listen_help="$("$bin" listen --help)"
service_help="$("$bin" service --help)"
help_help="$("$bin" help --help)"
version_help="$("$bin" version --help)"

expect_exact_stdout "root -h equals root --help" "$root_help" "$bin" -h
expect_exact_stdout "check -h equals check --help" "$check_help" "$bin" check -h
expect_exact_stdout "version -h equals version --help" "$version_help" "$bin" version -h
expect_exact_stdout "help -h equals help --help" "$help_help" "$bin" help -h
expect_exact_stdout "check --help succeeds without config" "$check_help" "$bin" check --help
expect_exact_stdout "run -h succeeds without config" "$run_help" "$bin" run --dry-run -h
expect_exact_stdout "service -h succeeds without action" "$service_help" "$bin" service -h
expect_exact_stdout "listen start -h succeeds without starting devices" "$listen_help" "$bin" listen start -h

expect_usage_failure "unknown root command prints only root help" "$root_help" "$bin" bogus
expect_usage_failure "unknown root command with flag prints only root help" "$root_help" "$bin" bogus --version
expect_usage_failure "unknown init option prints only init help" "$init_help" "$bin" init -x
expect_usage_failure "unknown check option prints only check help" "$check_help" "$bin" check --faster
expect_usage_failure "subcommand -v remains invalid and prints focused help" "$check_help" "$bin" check -v
expect_usage_failure "unknown run option prints only run help" "$run_help" "$bin" run --faster
expect_usage_failure "listen without action prints only listen help" "$listen_help" "$bin" listen
expect_usage_failure "unknown listen action prints only listen help" "$listen_help" "$bin" listen stop
expect_usage_failure "extra listen operand prints only listen help" "$listen_help" "$bin" listen start extra
expect_usage_failure "unknown service action prints only service help" "$service_help" "$bin" service nope
expect_usage_failure "unknown help topic prints only help help" "$help_help" "$bin" help bogus
expect_usage_failure "unknown version option prints only version help" "$version_help" "$bin" version --faster
expect_usage_failure "check without config prints only check help" "$check_help" "$bin" check
expect_usage_failure "run without config prints only run help" "$run_help" "$bin" run
expect_usage_failure "run --dry-run without config prints only run help" "$run_help" \
  "$bin" run --dry-run
expect_usage_failure "service without action prints only service help" "$service_help" "$bin" service

missing_configuration="$test_tmp/missing.toml"
expect_error "runtime config failure keeps diagnostics" "Error: Cannot load configuration" \
  "$bin" check "$missing_configuration"
expect_error "runtime config failure keeps root recovery guidance" \
  "Run aerospace-gestures --help for usage and recovery steps." \
  "$bin" check "$missing_configuration"

if ((failures)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
printf 'all CLI UX checks passed\n'
