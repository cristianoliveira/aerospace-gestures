#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

source="$tmp/build/cafune"
mkdir -p "$(dirname "$source")"
printf '#!/bin/sh\nprintf "Cafuné test binary\\n"\n' > "$source"
chmod 755 "$source"

archive="$("$root/scripts/package-release-archive.sh" "$source" "$tmp/dist" v1.2.3 arm64)"
test "$archive" = "$tmp/dist/cafune-v1.2.3-darwin-arm64.tar.gz"
python3 - "$archive" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    entries = archive.getmembers()
    assert [entry.name for entry in entries] == ["cafune"], entries
    assert entries[0].mode & 0o777 == 0o755, oct(entries[0].mode)
    assert archive.extractfile(entries[0]).read().startswith(b"#!/bin/sh")
PY

if "$root/scripts/package-release-archive.sh" "$tmp/missing" "$tmp/other" v1.2.3 arm64 \
  >"$tmp/out" 2>&1; then
  echo 'release packager unexpectedly accepted a missing executable' >&2
  exit 1
fi
test ! -e "$tmp/other/cafune-v1.2.3-darwin-arm64.tar.gz"

if "$root/scripts/package-release-archive.sh" "$source" "$tmp/unsafe" '../escape' arm64 \
  >"$tmp/out" 2>&1; then
  echo 'release packager unexpectedly accepted a path-like tag' >&2
  exit 1
fi
if "$root/scripts/package-release-archive.sh" "$source" "$tmp/unsupported" v1.2.3 x86_64 \
  >"$tmp/out" 2>&1; then
  echo 'release packager unexpectedly accepted an unsupported architecture' >&2
  exit 1
fi

printf 'release archive tests passed\n'
