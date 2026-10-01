#!/usr/bin/env bash
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log_dir="${CHECK_LOG_DIR:-$root/.tmp/check}"
swift_bin="${SWIFT_BIN:-swift}"
mkdir -p "$log_dir" || { printf 'false\nUnable to create gate log directory\n'; exit 1; }
log="$log_dir/gate-$(date +%Y%m%dT%H%M%S)-$$.log"
shopt -s nullglob
logs=("$log_dir"/gate-*.log)
if ((${#logs[@]} >= 10)); then
  while IFS= read -r old_log; do
    rm -f "$old_log"
  done < <(ls -t "${logs[@]}" | tail -n +10)
fi
: >"$log" || { printf 'false\nUnable to create gate log\n'; exit 1; }

failed=0
steps=(release-notes-test cli-ux-test build test install-test)
if [[ "${CHECK_SKIP_GUARDRAILS:-0}" != 1 ]]; then
  steps=(guardrails "${steps[@]}")
fi
for step in "${steps[@]}"; do
  case "$step" in
    guardrails) command=("$root/scripts/test-guardrails.sh") ;;
    release-notes-test) command=("$root/scripts/test-extract-release-notes.sh") ;;
    cli-ux-test) command=("$root/scripts/test-cli-ux.sh") ;;
    build) command=("$swift_bin" build -Xswiftc -warnings-as-errors) ;;
    test) command=("$swift_bin" test) ;;
    install-test) command=("$root/scripts/test-install.sh") ;;
  esac
  printf '$' >>"$log"
  printf ' %q' "${command[@]}" >>"$log"
  printf '\n' >>"$log"
  "${command[@]}" >>"$log" 2>&1 || failed=1
done

if (( failed )); then
  printf 'false\n'
  tail -n 24 "$log" | cut -c1-500
  printf 'Full log: %s\n' "$log"
  exit 1
fi
printf 'true\n'
