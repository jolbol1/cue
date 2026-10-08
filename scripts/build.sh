#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/cue-clang-cache"
SWIFT_CACHE="${TMPDIR:-/tmp}/cue-swift-cache"
# SwiftPM records the deployment target as the SDK version, which runs the app in
# compatibility mode on newer macOS. Record the real SDK so Cue gets the current system design.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build -c release --disable-sandbox -Xswiftc -module-cache-path -Xswiftc "$SWIFT_CACHE" \
  -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION"
APP="$PWD/dist/Cue.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Cue "$APP/Contents/MacOS/Cue"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/Cue.icns ]]; then cp Resources/Cue.icns "$APP/Contents/Resources/Cue.icns"; fi
codesign --force --sign - --identifier com.james.cue --entitlements Resources/Cue.entitlements "$APP"
echo "Built $APP"
