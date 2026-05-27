#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${CONFIGURATION:-release}"
app_name="AI Fuel Gauge"
bundle_id="com.ozansozuoz.aifuelgauge"
dist_dir="$repo_root/dist"
app_path="$dist_dir/$app_name.app"
contents="$app_path/Contents"
macos_dir="$contents/MacOS"
resources_dir="$contents/Resources"

cd "$repo_root"
swift build -c "$configuration" --product aifuelgauge

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
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$app_path" >/dev/null 2>&1 || true
fi

echo "$app_path"
