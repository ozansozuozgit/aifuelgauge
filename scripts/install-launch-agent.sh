#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_source="$("$repo_root/scripts/package-app.sh" | tail -n 1)"
install_dir="$HOME/Applications"
app_name="AI Fuel Gauge.app"
app_dest="$install_dir/$app_name"
label="com.ozansozuoz.aifuelgauge"
plist="$HOME/Library/LaunchAgents/$label.plist"

if [[ ! -d "$app_source" ]]; then
  echo "Packaged app not found at: $app_source" >&2
  exit 1
fi

mkdir -p "$install_dir" "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true

dist_executable="$repo_root/dist/$app_name/Contents/MacOS/aifuelgauge"
ps -axo pid=,command= | while read -r pid command; do
  if [[ "$command" == "$dist_executable"* ]]; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
done

rm -rf "$app_dest"
cp -R "$app_source" "$app_dest"
if [[ "$app_source" == "$repo_root/dist/$app_name" ]]; then
  rm -rf "$app_source"
fi

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$app_dest/Contents/MacOS/aifuelgauge</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$HOME/Library/Logs/aifuelgauge.log</string>
  <key>StandardErrorPath</key>
  <string>$HOME/Library/Logs/aifuelgauge.log</string>
</dict>
</plist>
PLIST

launchctl bootstrap "gui/$(id -u)" "$plist"
launchctl enable "gui/$(id -u)/$label"
launchctl kickstart -k "gui/$(id -u)/$label"

echo "Installed $app_dest and enabled LaunchAgent $plist"
