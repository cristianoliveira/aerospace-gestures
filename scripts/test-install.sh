#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

source="$tmp/release/aerospace-gestures"
mkdir -p "$(dirname "$source")"
printf 'first build\n' > "$source"
chmod 755 "$source"

"$root/scripts/install-binary.sh" "$source" "$tmp/home/.local/bin"
target="$tmp/home/.local/bin/aerospace-gestures"
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
test ! -e "$tmp/other/bin/aerospace-gestures"

printf 'install tests passed\n'
