#!/bin/bash
# Builds 朝夕 for iPhone and installs it on the connected phone. Free signing lasts 7 days: run this again to renew.
set -euo pipefail
cd "$(dirname "$0")"

# A real (not simulated) iPhone that is connected by cable or on the same Wi-Fi.
FOUND=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
try: devices = json.load(sys.stdin)["result"]["devices"]
except Exception: devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("reality") != "simulated" and hw.get("platform") == "iOS" and d.get("connectionProperties", {}).get("tunnelState") != "unavailable":
        print(hw.get("udid") or d["identifier"], d.get("connectionProperties", {}).get("pairingState", "")); break
')
DEVICE=${FOUND%% *}
if [ -z "$DEVICE" ]; then
  echo "没有找到 iPhone：请用数据线连接 iPhone，解锁后在手机上点「信任此电脑」，再运行一次。"
  exit 1
fi
if [ "${FOUND#* }" != "paired" ]; then
  echo "请在 iPhone 上点「信任」并输入锁屏密码…"
  xcrun devicectl manage pair --device "$DEVICE" >/dev/null
fi

xcodegen generate --quiet
mkdir -p build.noindex  # .noindex: Spotlight skips it, so build copies never show up as extra 朝夕 apps
xcodebuild -project Cre.xcodeproj -scheme TideMobile -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build.noindex/dd-ios -allowProvisioningUpdates -quiet build || {
  echo "装不上，常见原因：① Xcode ▸ 设置 ▸ Accounts 未登录 Apple ID；② iPhone 未解锁或未开 设置 ▸ 隐私与安全性 ▸ 开发者模式。"
  exit 1
}

APP=build.noindex/dd-ios/Build/Products/Release-iphoneos/Tide.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
# The build copy stays out of Launchpad / Spotlight.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" >/dev/null 2>&1 || true
echo "已装到 iPhone。第一次打开如提示「不受信任的开发者」：设置 ▸ 通用 ▸ VPN 与设备管理 ▸ 信任。"
echo "7 天后需要再运行一次本脚本。"
