#!/usr/bin/env bash
set -euo pipefail

binary=${1:?Expected built cafune executable}
dist_dir=${2:?Expected output directory}
release_tag=${3:?Expected release tag}
package_arch=${4:?Expected package architecture}

if [[ ! "$release_tag" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
  echo "Cannot package: invalid release tag: $release_tag" >&2
  exit 1
fi
case "$package_arch" in
  arm64 | amd64) ;;
  *) echo "Cannot package: unsupported architecture: $package_arch" >&2; exit 1 ;;
esac

if [[ -L "$binary" || ! -f "$binary" || ! -x "$binary" ]]; then
  echo "Cannot package: executable is missing or invalid: $binary" >&2
  exit 1
fi

mkdir -p "$dist_dir/payload"
payload="$dist_dir/payload/cafune"
if [[ -e "$payload" || -L "$payload" ]]; then
  echo "Cannot package: output already exists: $payload" >&2
  exit 1
fi
cp "$binary" "$payload"
chmod 755 "$payload"

archive="$dist_dir/cafune-${release_tag}-darwin-${package_arch}.tar.gz"
python3 - "$archive" "$payload" <<'PY'
import gzip
import sys
import tarfile

archive_path, binary_path = sys.argv[1:]
with open(archive_path, "wb") as archive_file:
    with gzip.GzipFile(
        filename="", fileobj=archive_file, mode="wb", mtime=0, compresslevel=9
    ) as compressed:
        with tarfile.open(
            fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT
        ) as archive:
            entry = archive.gettarinfo(binary_path, arcname="cafune")
            entry.uid = entry.gid = 0
            entry.uname = entry.gname = ""
            entry.mtime = 0
            entry.mode = 0o755
            with open(binary_path, "rb") as binary_file:
                archive.addfile(entry, binary_file)
PY

entries=$(tar -tzf "$archive")
if [[ "$entries" != "cafune" ]]; then
  echo "Unexpected archive contents: $entries" >&2
  exit 1
fi

printf '%s\n' "$archive"
