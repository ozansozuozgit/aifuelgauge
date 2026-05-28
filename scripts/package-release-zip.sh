#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${VERSION:-$(git -C "$repo_root" describe --tags --always --dirty 2>/dev/null || echo dev)}"
safe_version="$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '-')"
app_path="$(VERSION="$version" "$repo_root/scripts/package-app.sh" | tail -n 1)"
zip_name="AI-Fuel-Gauge-$safe_version.zip"
zip_path="$repo_root/dist/$zip_name"
latest_zip_path="$repo_root/dist/AI-Fuel-Gauge-latest.zip"

if [[ ! -d "$app_path" ]]; then
  echo "Packaged app not found at: $app_path" >&2
  exit 1
fi

rm -f "$zip_path" "$zip_path.sha256" "$latest_zip_path" "$latest_zip_path.sha256"

create_zip() {
  local output_path="$1"
  rm -f "$output_path"
  if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --keepParent "$app_path" "$output_path"
  else
    (
      cd "$(dirname "$app_path")"
      zip -qry "$output_path" "$(basename "$app_path")"
    )
  fi
}

create_zip "$zip_path"

if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is required for notarization" >&2
    exit 1
  fi
  echo "Submitting $zip_name for notarization..." >&2
  xcrun notarytool submit "$zip_path" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait >&2
  xcrun stapler staple "$app_path" >&2
  create_zip "$zip_path"
fi

shasum -a 256 "$zip_path" > "$zip_path.sha256"
cp "$zip_path" "$latest_zip_path"
shasum -a 256 "$latest_zip_path" > "$latest_zip_path.sha256"
echo "$zip_path"
