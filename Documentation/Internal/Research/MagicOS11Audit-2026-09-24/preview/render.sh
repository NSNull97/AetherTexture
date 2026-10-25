#!/bin/zsh
set -euo pipefail
HERE=${0:A:h}
DEVICE=${1:-D0AE9B34-436F-4D77-927C-AD820F80D10B}
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
APP="$HERE/build/AetherGlassAudit.app"
mkdir -p "$APP" "$HERE/../screenshots"
xcrun swiftc -sdk "$SDK" -target arm64-apple-ios26.0-simulator -parse-as-library -module-name AetherGlassAudit -o "$APP/AetherGlassAudit" "$HERE/Preview.swift" -framework UIKit
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AetherGlassAudit</string>
<key>CFBundleIdentifier</key><string>com.aetherui.research.glassaudit20260924</string>
<key>CFBundleName</key><string>Aether Glass Audit</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>26.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
<key>UIRequiresFullScreen</key><true/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
trap 'xcrun simctl status_bar "$DEVICE" clear >/dev/null 2>&1 || true' EXIT
xcrun simctl status_bar "$DEVICE" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
for mode in components chat dark; do
  xcrun simctl terminate "$DEVICE" com.aetherui.research.glassaudit20260924 2>/dev/null || true
  xcrun simctl launch "$DEVICE" com.aetherui.research.glassaudit20260924 "$mode"
  sleep 3
  xcrun simctl io "$DEVICE" screenshot "$HERE/../screenshots/proposal-$mode.png"
done
