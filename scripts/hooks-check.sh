#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
actual="$(git config --get core.hooksPath || true)"
if [[ "$actual" != ".githooks" ]]; then
  printf 'Hooks are not installed (core.hooksPath=%s); run make hooks-install\n' "${actual:-unset}" >&2
  exit 1
fi
for hook in pre-commit pre-push commit-msg; do
  if [[ ! -x ".githooks/$hook" ]]; then
    printf 'Missing executable hook: .githooks/%s\n' "$hook" >&2
    exit 1
  fi
done
printf 'Versioned hooks are installed\n'
