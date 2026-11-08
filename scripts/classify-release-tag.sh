#!/usr/bin/env bash
# Classify supported tags without accepting arbitrary prerelease/build metadata.
set -euo pipefail

if (($# != 1)); then
  printf 'usage: %s <tag>\n' "${0##*/}" >&2
  exit 2
fi

tag=$1
if [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'stable\n'
  exit 0
fi
if [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+-alpha\.[1-9][0-9]*$ ]]; then
  printf 'prerelease\n'
  exit 0
fi

printf 'unsupported release tag %q; expected vX.Y.Z or vX.Y.Z-alpha.N (N > 0)\n' "$tag" >&2
exit 1
