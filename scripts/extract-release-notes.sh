#!/usr/bin/env bash
# Print the CHANGELOG section for a tag (the exact "## <tag>" heading) for use in
# release notes. Fails closed when the heading is missing or the section is empty,
# so a release cannot ship without its documented notes.
set -euo pipefail

if (($# < 1 || $# > 2)); then
  printf 'usage: %s <tag> [changelog]\n' "${0##*/}" >&2
  exit 2
fi
tag=$1
changelog=${2:-CHANGELOG.md}

[[ -f $changelog ]] || {
  printf 'no changelog at %s\n' "$changelog" >&2
  exit 1
}

notes="$(awk -v heading="## $tag" '
  $0 == heading { seen = 1; next }
  seen && /^## / { exit }
  seen { print }
' "$changelog")"

# Trim blank edges so a heading followed by blank lines is still an empty section.
notes="${notes#"${notes%%[![:space:]]*}"}"
notes="${notes%"${notes##*[![:space:]]}"}"

[[ -n $notes ]] || {
  printf 'no non-empty "## %s" section in %s\n' "$tag" "$changelog" >&2
  exit 1
}
printf '%s\n' "$notes"
