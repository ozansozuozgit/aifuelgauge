#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_name="AI Fuel Gauge"
bundle_id="com.ozansozuoz.aifuelgauge"
raw_app_version="${VERSION:-0.1.0}"
app_version="$(printf '%s' "$raw_app_version" | sed -E 's/^[vV]//' | sed -E 's/^([0-9]+([.][0-9]+){0,2}).*/\1/')"
if [[ ! "$app_version" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  app_version="0.1.0"
fi
build_version="$(printf '%s' "$app_version" | tr -cd '0-9' | sed 's/^0*//')"
build_version="${build_version:-1}"
dist_dir="$repo_root/dist"
app_path="$dist_dir/$app_name.app"
contents="$app_path/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"
iconset_path="$dist_dir/AppIcon.iconset"

cd "$repo_root"
swift build -c "$configuration" --product aifuelgauge >&2

rm -rf "$app_path"
mkdir -p "$macos_dir" "$resources_dir"
cp "$repo_root/.build/$configuration/aifuelgauge" "$macos_dir/aifuelgauge"
chmod +x "$macos_dir/aifuelgauge"

cat > "$contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundleExecutable</key>
  <string>aifuelgauge</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$app_version</string>
  <key>CFBundleVersion</key>
  <string>$build_version</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$contents/PkgInfo"
"$repo_root/scripts/build-app-icon.swift" "$iconset_path" >&2
iconutil -c icns "$iconset_path" -o "$resources_dir/AppIcon.icns" >&2
rm -rf "$iconset_path"

if command -v codesign >/dev/null 2>&1; then
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_path" >&2
  else
    codesign --force --deep --sign - "$app_path" >/dev/null 2>&1 || true
  fi
fi

echo "$app_path"
