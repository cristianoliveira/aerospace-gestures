#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

source="$tmp/release/cafune"
legacy="$tmp/home/.local/bin/aerospace-gestures"
mkdir -p "$(dirname "$source")" "$(dirname "$legacy")"
printf 'first build\n' > "$source"
chmod 755 "$source"
printf 'legacy build\n' > "$legacy"
chmod 755 "$legacy"

"$root/scripts/install-binary.sh" "$source" "$tmp/home/.local/bin"
target="$tmp/home/.local/bin/cafune"
test "$(cat "$legacy")" = 'legacy build'
test -x "$target"
test "$(cat "$target")" = 'first build'

printf 'second build\n' > "$source"
if "$root/scripts/install-binary.sh" "$source" "$tmp/home/.local/bin" > "$tmp/out" 2>&1; then
  echo 'install unexpectedly replaced an existing binary' >&2
  exit 1
fi
test "$(cat "$target")" = 'first build'

rm "$target"
ln -s "$source" "$target"
if "$root/scripts/install-binary.sh" "$source" "$tmp/home/.local/bin" > "$tmp/out" 2>&1; then
  echo 'install unexpectedly replaced a symlink' >&2
  exit 1
fi
test -L "$target"

if "$root/scripts/install-binary.sh" "$tmp/missing" "$tmp/other/bin" > "$tmp/out" 2>&1; then
  echo 'install unexpectedly accepted a missing build' >&2
  exit 1
fi
test ! -e "$tmp/other/bin/cafune"

printf 'install tests passed\n'
