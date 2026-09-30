#!/bin/sh
set -eu

source=${1:?Expected release binary path}
directory=${2:?Expected installation directory}
target="$directory/aerospace-gestures"

if [ -L "$source" ] || [ ! -f "$source" ] || [ ! -x "$source" ]; then
  echo "Cannot install: build the release executable first: $source" >&2
  exit 1
fi
if [ -L "$directory" ]; then
  echo "Cannot install into a symlinked directory: $directory" >&2
  exit 1
fi
if [ -e "$target" ] || [ -L "$target" ]; then
  echo "Cannot install: $target already exists. Stop the service and follow the update procedure in README.md." >&2
  exit 1
fi

mkdir -p "$directory"
staged=$(mktemp "$directory/.aerospace-gestures.XXXXXX")
trap 'rm -f "$staged"' EXIT HUP INT TERM
cp "$source" "$staged"
chmod 755 "$staged"

# A hard link publishes the staged binary atomically and refuses an existing target.
if ! ln "$staged" "$target"; then
  echo "Cannot install: $target already exists or cannot be created" >&2
  exit 1
fi
printf 'Installed %s\n' "$target"
