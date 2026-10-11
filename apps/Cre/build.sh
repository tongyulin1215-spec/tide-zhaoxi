#!/bin/bash
# Builds Tide.app (朝夕) (with its desktop widget) and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
mkdir -p build.noindex  # .noindex: Spotlight skips it, so build copies never show up as extra 朝夕 apps
xcodebuild -project Cre.xcodeproj -scheme Cre -configuration Release \
  -derivedDataPath build.noindex/dd -allowProvisioningUpdates -quiet build

APP="build.noindex/dd/Build/Products/Release/Tide.app"
DEST="$HOME/Applications/Tide.app"
osascript -e 'tell application id "com.lty.cre" to quit' >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$APP" "$DEST"
# The app was called Cre, then Planner, before; remove that copy (data lives in the shared container, untouched).
rm -rf "$HOME/Applications/Cre.app" "$HOME/Applications/Planner.app" build.noindex/Cre.app
# Only the installed copy may be registered, or the widget gallery picks up a stale name.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREG" -u "$APP" "build.noindex/dd/Build/Products/Release/TideWidget.appex" >/dev/null 2>&1 || true
"$LSREG" -f "$DEST"
pluginkit -r "build.noindex/dd/Build/Products/Release/CreWidget.appex" >/dev/null 2>&1 || true
pluginkit -a "$DEST/Contents/PlugIns/TideWidget.appex" || true
echo "Installed: $DEST"
