#!/usr/bin/env bash
# Behavioral tests for extract-release-notes.sh: real file fixtures, exit codes, exact output.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
extract="$root/scripts/extract-release-notes.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
expect_output() { # description tag changelog expected
  local description=$1 tag=$2 changelog=$3 expected=$4 actual status
  actual="$("$extract" "$tag" "$changelog" 2>/dev/null)" && status=0 || status=$?
  if [[ $status -ne 0 || $actual != "$expected" ]]; then
    printf 'FAIL: %s (status %s)\n' "$description" "$status"
    failures=$((failures + 1))
  else
    printf 'ok: %s\n' "$description"
  fi
}

expect_failure() { # description tag changelog
  local description=$1 tag=$2 changelog=$3 output status
  output="$("$extract" "$tag" "$changelog" 2>/dev/null)" && status=0 || status=$?
  if [[ $status -eq 0 || -n $output ]]; then
    printf 'FAIL: %s (status %s, output %q)\n' "$description" "$status" "$output"
    failures=$((failures + 1))
  else
    printf 'ok: %s\n' "$description"
  fi
}

cat >"$tmp/CHANGELOG.md" <<'EOF'
# Changelog

## v0.1.0

Old section.

## v0.2.0

**Breaking: TOML-only config.**

Details line.

### Subheading kept

- list item

## v0.3.0

Future.
EOF

expected_v020='**Breaking: TOML-only config.**

Details line.

### Subheading kept

- list item'

expect_output "extracts the matching middle section with subheadings" \
  v0.2.0 "$tmp/CHANGELOG.md" "$expected_v020"
expect_output "extracts the final section to end of file" \
  v0.3.0 "$tmp/CHANGELOG.md" "Future."
expect_failure "fails closed when the heading is missing" v9.9.9 "$tmp/CHANGELOG.md"

printf '## v0.4.0\n' >"$tmp/EMPTY.md"
expect_failure "fails closed on a heading-only section" v0.4.0 "$tmp/EMPTY.md"

: >"$tmp/BLANK.md"
expect_failure "fails closed on an empty changelog" v0.1.0 "$tmp/BLANK.md"

if ((failures)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
printf 'all release-notes extraction tests passed\n'
