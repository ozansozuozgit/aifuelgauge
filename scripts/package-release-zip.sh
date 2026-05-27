#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${VERSION:-$(git -C "$repo_root" describe --tags --always --dirty 2>/dev/null || echo dev)}"
safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
app_path="$("$repo_root/scripts/package-app.sh" | tail -n 1)"
zip_name="AI-Fuel-Gauge-$safe_version.zip"
zip_path="$repo_root/dist/$zip_name"

if [[ ! -d "$app_path" ]]; then
  echo "Packaged app not found at: $app_path" >&2
  exit 1
fi

rm -f "$zip_path" "$zip_path.sha256"

if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --keepParent "$app_path" "$zip_path"
else
  (
    cd "$(dirname "$app_path")"
    zip -qry "$zip_path" "$(basename "$app_path")"
  )
fi

shasum -a 256 "$zip_path" > "$zip_path.sha256"
echo "$zip_path"
