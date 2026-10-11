#!/bin/bash
# Builds the public edition of 朝夕 (example data, opens on any Mac) into dist/朝夕-演示版-Mac.zip.
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate --quiet
mkdir -p build.noindex dist
xcodebuild -project Cre.xcodeproj -scheme TideDemo -configuration Release -destination "generic/platform=macOS" \
  -derivedDataPath build.noindex/dd-demo -quiet build
APP="build.noindex/dd-demo/Build/Products/Release/TideDemo.app"
# Keep the build copy out of Launchpad / Spotlight on this Mac.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" >/dev/null 2>&1 || true
rm -rf "dist/朝夕.app" "dist/朝夕-演示版-Mac.zip"
ditto "$APP" "dist/朝夕.app"
ditto -c -k --sequesterRsrc --keepParent "dist/朝夕.app" "dist/朝夕-演示版-Mac.zip"
rm -rf "dist/朝夕.app"
echo "dist/朝夕-演示版-Mac.zip"
