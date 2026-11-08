#!/usr/bin/env bash
# Behavioral tests for supported stable and alpha release tags.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
classify="$root/scripts/classify-release-tag.sh"
failures=0

expect_kind() { # tag expected
  local tag=$1 expected=$2 actual status
  actual="$($classify "$tag" 2>/dev/null)" && status=0 || status=$?
  if [[ $status -ne 0 || $actual != "$expected" ]]; then
    printf 'FAIL: %s classified as %q (status %s)\n' "$tag" "$actual" "$status"
    failures=$((failures + 1))
  else
    printf 'ok: %s -> %s\n' "$tag" "$expected"
  fi
}

expect_invalid() { # tag
  local tag=$1 actual status
  actual="$($classify "$tag" 2>/dev/null)" && status=0 || status=$?
  if [[ $status -eq 0 || -n $actual ]]; then
    printf 'FAIL: rejected-tag case %s returned %q (status %s)\n' "$tag" "$actual" "$status"
    failures=$((failures + 1))
  else
    printf 'ok: rejected %s\n' "$tag"
  fi
}

expect_kind v0.7.0-alpha.1 prerelease
expect_kind v0.7.0-alpha.12 prerelease
expect_kind v0.6.0 stable
expect_kind v2.10.3 stable
expect_invalid v0.7.0-alpha.0
expect_invalid v0.7.0-alpha.01
expect_invalid v0.7.0-beta.1
expect_invalid v0.7.0-rc.1
expect_invalid v0.7.0-alpha
expect_invalid 0.7.0-alpha.1
expect_invalid v0.7.0-alpha.1+build

if ((failures)); then
  printf '%d failure(s)\n' "$failures"
  exit 1
fi
printf 'all release-tag classification tests passed\n'
