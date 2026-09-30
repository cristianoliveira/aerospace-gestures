#!/usr/bin/env bash
set -u

if (($# != 1)) || [[ ! -f "$1" ]]; then
  printf 'Usage: %s <commit-message-file>\n' "$0" >&2
  exit 2
fi
message="$(head -n 1 "$1")"
pattern='^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test|plans)(\([[:alnum:]./_-]+\))?!?: .+'
if [[ "$message" =~ $pattern ]]; then
  exit 0
fi
printf 'Invalid commit subject: %s\nExpected conventional format, e.g. feat(cli): add option or plans(new): add task\n' "$message" >&2
exit 1
