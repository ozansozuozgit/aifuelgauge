#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# SwiftPM menu-bar runs are easy to leave behind while iterating. Kill this
# repo's debug executable so the menu bar never points at stale code.
while IFS= read -r pid; do
  [[ -z "$pid" ]] && continue
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$command" == *"$repo_root/.build/"*"/debug/aifuelgauge"* || "$command" == *".build/"*"/debug/aifuelgauge"* ]]; then
    kill "$pid" 2>/dev/null || true
  elif lsof -p "$pid" 2>/dev/null | grep -q "$repo_root/.build/.*/debug/aifuelgauge"; then
    kill "$pid" 2>/dev/null || true
  fi
done < <(pgrep -x aifuelgauge 2>/dev/null || true)

cd "$repo_root"
exec swift run aifuelgauge
