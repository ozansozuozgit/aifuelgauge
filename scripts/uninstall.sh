#!/usr/bin/env bash
set -euo pipefail

label="com.ozansozuoz.aifuelgauge"
plist="$HOME/Library/LaunchAgents/$label.plist"
app_dest="$HOME/Applications/AI Fuel Gauge.app"

launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
launchctl disable "gui/$(id -u)/$label" >/dev/null 2>&1 || true
rm -f "$plist"
rm -rf "$app_dest"

echo "Removed $app_dest and LaunchAgent $plist"
