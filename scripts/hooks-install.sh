#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
current="$(git config --get core.hooksPath || true)"
if [[ -n "$current" && "$current" != ".githooks" ]]; then
  printf 'Refusing to replace existing core.hooksPath=%s\n' "$current" >&2
  exit 1
fi
if [[ -z "$current" ]]; then
  hooks_dir="$(git rev-parse --git-path hooks)"
  for existing in "$hooks_dir"/*; do
    [[ -e "$existing" || -L "$existing" ]] || continue
    name="${existing##*/}"
    [[ "$name" == *.sample ]] && continue
    if [[ -x "$existing" ]]; then
      printf 'Refusing to bypass existing executable hook: %s\n' "$existing" >&2
      printf 'Integrate it into .githooks/%s, then retry.\n' "$name" >&2
      exit 1
    fi
  done
  git config --local core.hooksPath .githooks
fi
printf 'Installed versioned hooks path: .githooks\n'
