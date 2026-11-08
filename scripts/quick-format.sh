#!/usr/bin/env bash
set -u

swift_files=()
for path in "$@"; do
  [[ "$path" == *.swift ]] || continue
  [[ -f "$path" ]] || continue
  swift_files+=("$path")
done

((${#swift_files[@]})) || exit 0
xcrun swift-format lint --strict "${swift_files[@]}"
