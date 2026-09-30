#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/aerospace-guardrails.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export GIT_CONFIG_GLOBAL="$tmp/global-config"
export GIT_CONFIG_NOSYSTEM=1
failures=0

assert() {
  if ! "$@"; then
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
  fi
}

expect_failure() {
  ! "$@" >/dev/null 2>&1
}

cat >"$tmp/fake-swift" <<'FAKE'
#!/usr/bin/env bash
printf 'fake swift %s\n' "$*"
case "${FAKE_MODE:-ok}:$1" in
  fail-build:build)
    for line in {1..80}; do printf 'failure detail %s\n' "$line"; done
    exit 7
    ;; 
  fail-test:test) exit 9 ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$tmp/fake-swift"

out="$(CHECK_SKIP_GUARDRAILS=1 SWIFT_BIN="$tmp/fake-swift" CHECK_LOG_DIR="$tmp/logs" "$root/scripts/check.sh")"
assert test "$out" = true

set +e
out="$(CHECK_SKIP_GUARDRAILS=1 FAKE_MODE=fail-build SWIFT_BIN="$tmp/fake-swift" CHECK_LOG_DIR="$tmp/logs" "$root/scripts/check.sh" 2>&1)"
status=$?
set -e
assert test "$status" -ne 0
assert test "${out%%$'\n'*}" = false
assert bash -c '[[ "$1" == *"Full log:"* ]]' _ "$out"
assert bash -c '(( $(printf "%s\n" "$1" | wc -l) <= 27 ))' _ "$out"
assert bash -c '(( ${#1} <= 14000 ))' _ "$out"
log_path="${out##*Full log: }"
assert bash -c 'grep -q "fake swift build" "$1" && grep -q "fake swift test" "$1"' _ "$log_path"
assert bash -c '[[ $(wc -l < "$1") -gt 80 ]]' _ "$log_path"

set +e
out="$(CHECK_SKIP_GUARDRAILS=1 FAKE_MODE=fail-test SWIFT_BIN="$tmp/fake-swift" CHECK_LOG_DIR="$tmp/logs" "$root/scripts/check.sh" 2>&1)"
status=$?
set -e
assert test "$status" -ne 0
assert test "${out%%$'\n'*}" = false
assert bash -c '[[ "$1" == *"fake swift test"* ]]' _ "$out"

for index in {1..11}; do
  : >"$tmp/logs/gate-seed-$index.log"
done
CHECK_SKIP_GUARDRAILS=1 SWIFT_BIN="$tmp/fake-swift" CHECK_LOG_DIR="$tmp/logs" "$root/scripts/check.sh" >/dev/null
assert bash -c '[[ $(find "$1" -maxdepth 1 -name "gate-*.log" | wc -l) -eq 10 ]]' _ "$tmp/logs"

printf 'feat(cli): add a safe mode\n' >"$tmp/valid-message"
printf 'nonsense without type\n' >"$tmp/invalid-message"
assert "$root/scripts/check-commit-message.sh" "$tmp/valid-message"
assert expect_failure "$root/scripts/check-commit-message.sh" "$tmp/invalid-message"
printf 'plans(new): add a task\n' >"$tmp/plans-message"
assert "$root/scripts/check-commit-message.sh" "$tmp/plans-message"

# Exercise hook installation in an isolated repository, including refusal to overwrite user setup.
git init -q "$tmp/repo"
mkdir -p "$tmp/repo/scripts" "$tmp/repo/.githooks"
cp "$root/scripts/hooks-install.sh" "$root/scripts/hooks-check.sh" "$tmp/repo/scripts/"
cp "$root/scripts/check-commit-message.sh" "$tmp/repo/scripts/"
cp "$root/.githooks/"* "$tmp/repo/.githooks/"
chmod +x "$tmp/repo/scripts/"*.sh "$tmp/repo/.githooks/"*
mkdir -p "$tmp/bin"
cat >"$tmp/bin/make" <<'MAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CALL_LOG"
exit "${MAKE_STATUS:-0}"
MAKE
chmod +x "$tmp/bin/make"
: >"$tmp/make-calls"
(cd "$tmp/repo" && PATH="$tmp/bin:$PATH" CALL_LOG="$tmp/make-calls" .githooks/pre-commit)
(cd "$tmp/repo" && PATH="$tmp/bin:$PATH" CALL_LOG="$tmp/make-calls" .githooks/pre-push)
assert bash -c '[[ $(wc -l < "$1") -eq 2 ]]' _ "$tmp/make-calls"
assert bash -c 'grep -q "check$" "$1"' _ "$tmp/make-calls"
set +e
(cd "$tmp/repo" && PATH="$tmp/bin:$PATH" CALL_LOG="$tmp/make-calls" MAKE_STATUS=8 .githooks/pre-commit)
status=$?
set -e
assert test "$status" -eq 8
printf 'feat(cli): valid\n' >"$tmp/hook-valid"
printf 'bad subject\n' >"$tmp/hook-invalid"
(cd "$tmp/repo" && .githooks/commit-msg "$tmp/hook-valid")
set +e
(cd "$tmp/repo" && .githooks/commit-msg "$tmp/hook-invalid") >/dev/null 2>&1
status=$?
set -e
assert test "$status" -ne 0
set +e
(cd "$tmp/repo" && scripts/hooks-check.sh) >/dev/null 2>&1
status=$?
set -e
assert test "$status" -ne 0
(cd "$tmp/repo" && scripts/hooks-install.sh >/dev/null)
(cd "$tmp/repo" && scripts/hooks-check.sh >/dev/null)
(cd "$tmp/repo" && scripts/hooks-install.sh >/dev/null)

# A configured unrelated path must be preserved and rejected.
git -C "$tmp/repo" config --local core.hooksPath custom-hooks
set +e
(cd "$tmp/repo" && scripts/hooks-install.sh) >/dev/null 2>&1
status=$?
set -e
assert test "$status" -ne 0
assert test "$(git -C "$tmp/repo" config --local --get core.hooksPath)" = custom-hooks

# An existing executable hook in Git's default hooks directory is not silently bypassed.
git init -q "$tmp/repo-with-hook"
mkdir -p "$tmp/repo-with-hook/scripts" "$tmp/repo-with-hook/.githooks" "$tmp/repo-with-hook/.git/hooks"
cp "$root/scripts/hooks-install.sh" "$tmp/repo-with-hook/scripts/"
cp "$root/.githooks/"* "$tmp/repo-with-hook/.githooks/"
chmod +x "$tmp/repo-with-hook/scripts/"* "$tmp/repo-with-hook/.githooks/"*
ln -s /usr/bin/true "$tmp/repo-with-hook/.git/hooks/pre-commit"
set +e
(cd "$tmp/repo-with-hook" && scripts/hooks-install.sh) >/dev/null 2>&1
status=$?
set -e
assert test "$status" -ne 0
assert test -z "$(git -C "$tmp/repo-with-hook" config --local --get core.hooksPath || true)"

# Any active default hook, including hooks beyond our managed names, blocks redirection.
git init -q "$tmp/repo-with-other-hook"
mkdir -p "$tmp/repo-with-other-hook/scripts" "$tmp/repo-with-other-hook/.git/hooks"
cp "$root/scripts/hooks-install.sh" "$tmp/repo-with-other-hook/scripts/"
chmod +x "$tmp/repo-with-other-hook/scripts/hooks-install.sh"
printf '#!/bin/sh\nexit 0\n' >"$tmp/repo-with-other-hook/.git/hooks/post-checkout"
chmod +x "$tmp/repo-with-other-hook/.git/hooks/post-checkout"
set +e
(cd "$tmp/repo-with-other-hook" && scripts/hooks-install.sh) >/dev/null 2>&1
status=$?
set -e
assert test "$status" -ne 0
assert test -z "$(git -C "$tmp/repo-with-other-hook" config --local --get core.hooksPath || true)"

# An effective global hooksPath is user setup too; installation must not shadow it.
git init -q "$tmp/repo-with-global-path"
custom_global="$tmp/custom-global-config"
git config --file "$custom_global" core.hooksPath user-hooks
set +e
(cd "$tmp/repo-with-global-path" && GIT_CONFIG_GLOBAL="$custom_global" scripts/hooks-install.sh) >/dev/null 2>&1
status=$?
set -e
assert test "$status" -ne 0
assert test -z "$(git -C "$tmp/repo-with-global-path" config --local --get core.hooksPath || true)"
assert test "$(GIT_CONFIG_GLOBAL="$custom_global" git -C "$tmp/repo-with-global-path" config --get core.hooksPath)" = user-hooks

if (( failures )); then
  printf '%s guardrail assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'Guardrail failure-path tests passed\n'
